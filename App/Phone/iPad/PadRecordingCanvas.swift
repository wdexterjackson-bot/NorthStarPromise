import NSPCore
import NSPDesignSystem
import NSPMedia
import PencilKit
import SwiftUI

/// The writing tool currently active on `PadRecordingCanvas` — shared with
/// `PadCanvasHeader`, which renders the palette that sets it.
enum PadTool: Equatable {
    case pointer, text, pen
}

/// iPad's signature capability (docs/07 §5, written against a reference
/// mockup — see that doc for the full description): a college-ruled
/// notebook page that appears while a meeting is recording. A dark header
/// (`PadCanvasHeader`) carries recording controls and a writing-tool
/// palette; the page below is ruled lines with a red margin rule and a
/// timestamp gutter. Typed lines and Apple Pencil ink both anchor to the
/// real sample offset they were created at
/// (`RecordingSession.currentSampleOffset()`), not the wall-clock label
/// shown in the margin.
///
/// Ink is grouped into `NoteBlock`s by `StrokeGroupTracker` rather than
/// saved as one page-wide block: strokes close together in time and
/// position share a `.sketch` block and its `creationRange`; a gap in
/// either closes the group (`NOT-002`, `NSP-101`).
///
/// Scope of this pass, honestly: no photo insertion, no highlighter, no
/// multi-page. Pre-recording availability (the canvas showing before the
/// user taps Record, with `--:--` stamps) also isn't built — this pass
/// only covers the already-recording case, since that's the state
/// `PadRootView` currently routes here for.
@MainActor
struct PadRecordingCanvas: View {
    let environment: AppEnvironment
    let session: RecordingSession

    @State private var lines: [PadNoteLine] = [PadNoteLine()]
    @FocusState private var focusedLineID: UUID?
    @State private var isConfirmingStop = false
    @State private var loadError: String?
    @State private var activeTool: PadTool = .pointer
    @State private var meetingTitle = ""
    @State private var drawing = PKDrawing()
    @State private var strokesByID: [UUID: PKStroke] = [:]
    @State private var strokeTracker: StrokeGroupTracker?
    @State private var idleGroupCloseTask: Task<Void, Never>?
    /// A synthetic, all-negative sample timeline for content created before
    /// recording starts (`state == .draft`) — increases monotonically just
    /// like the real one, so ordering/grouping logic that compares sample
    /// offsets keeps working unmodified, but every value sorts before any
    /// real (non-negative) offset and is unambiguously "pre-recording" for
    /// the `--:--` margin stamp (docs/07 §5). Never persisted as a claim
    /// about real elapsed time — it just needs to be negative and ordered.
    @State private var nextPreRecordingSampleOffset: Int64 = -1_000_000_000_000

    private static let idleGroupCloseDelay: Duration = .seconds(2)

    var body: some View {
        VStack(spacing: 0) {
            PadCanvasHeader(
                session: session, activeTool: $activeTool, isConfirmingStop: $isConfirmingStop,
                onSelectNonPenTool: {
                    focusedLineID = focusedLineID ?? lines.first?.id
                    Task { await closeOpenInkGroupIfNeeded() }
                })
            ZStack(alignment: .topLeading) {
                page
                PadInkCanvas(drawing: $drawing, isActive: activeTool == .pen, onDrawingChanged: handleDrawingChange)
                    .allowsHitTesting(activeTool == .pen)
            }
        }
        .background(NSPColor.background)
        .task {
            await loadMeetingTitle()
            await loadExistingLines()
            await loadExistingInk()
        }
        .onAppear { focusedLineID = lines.first?.id }
        .onDisappear { Task { await closeOpenInkGroupIfNeeded() } }
        .confirmationDialog(
            "Stop recording?", isPresented: $isConfirmingStop, titleVisibility: .visible
        ) {
            Button("Stop Recording", role: .destructive) {
                Task {
                    await closeOpenInkGroupIfNeeded()
                    await session.stop()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            TextField("Meeting name", text: $meetingTitle)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .onSubmit { Task { await saveMeetingTitle() } }
                .padding(.top, NSPSpacing.extraLarge)
                .padding(.bottom, NSPSpacing.large)
                .frame(maxWidth: .infinity)

            LazyVStack(spacing: 0) {
                ForEach($lines) { $line in
                    PadNoteLineRow(line: $line, focusedLineID: $focusedLineID)
                        .onChange(of: line.text) { oldValue, newValue in
                            Task { await handleTextChange(lineID: line.id, oldValue: oldValue, newValue: newValue) }
                        }
                        .onSubmit { addLine(after: line.id) }
                }
            }
            .padding(.horizontal, NSPSpacing.large)
            .frame(minHeight: 1400, alignment: .top)
            .background(alignment: .topLeading) { marginRule }
        }
        .background(Color.white)
        .onDisappear { Task { await saveMeetingTitle() } }
    }

    /// The red vertical rule + timestamp gutter, matching the mockup —
    /// drawn once behind every ruled line rather than per-row, so it reads
    /// as one continuous margin the way real notebook paper does.
    private var marginRule: some View {
        Rectangle()
            .fill(Color.red.opacity(0.55))
            .frame(width: 1.5)
            .padding(.leading, 60)
            .allowsHitTesting(false)
    }

    // MARK: - Meeting title

    private func loadMeetingTitle() async {
        guard let meetingID = session.meetingID, let meeting = try? await environment.meetingRepository.find(meetingID)
        else { return }
        meetingTitle = meeting.title
    }

    private func saveMeetingTitle() async {
        guard let meetingID = session.meetingID,
            var meeting = try? await environment.meetingRepository.find(meetingID)
        else { return }
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meeting.title else { return }
        meeting.title = trimmed
        try? await environment.meetingRepository.update(meeting, at: environment.clock.now())
    }

    // MARK: - Typed lines

    private func addLine(after id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let newLine = PadNoteLine()
        lines.insert(newLine, at: index + 1)
        focusedLineID = newLine.id
    }

    private func handleTextChange(lineID: UUID, oldValue: String, newValue: String) async {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        if oldValue.isEmpty, !newValue.isEmpty, lines[index].block == nil {
            await createBlock(atLineIndex: index)
        } else if lines[index].block != nil {
            await updateBlock(atLineIndex: index, text: newValue)
        }
    }

    private func createBlock(atLineIndex index: Int) async {
        guard let meetingID = session.meetingID, let selfPersonID = environment.selfPersonID else { return }
        let isPreRecording = session.state == .draft
        let sampleOffset =
            isPreRecording ? reservePreRecordingSampleOffset() : (await session.currentSampleOffset() ?? 0)
        let now = environment.clock.now()
        let text = lines[index].text
        let block = NoteBlock(
            blockID: NoteBlockID(rawValue: UUID()), meetingID: meetingID, authorID: selfPersonID, type: .richText,
            content: .text(text), creationRange: SampleRange(startSample: sampleOffset, endSample: sampleOffset),
            privacy: .shared,
            opLog: [Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(text))])
        do {
            try await environment.noteBlockRepository.insert(block, at: now)
            lines[index].block = block
            // A `--:--` stamp is permanent once assigned (docs/07 §5): this
            // is the only place that sets it for a freshly-created line, and
            // nothing later recomputes it from `session.elapsedSeconds`.
            lines[index].timestampLabel = isPreRecording ? "--:--" : Self.formatElapsed(session.elapsedSeconds)
        } catch {
            loadError = "\(error)"
        }
    }

    /// Hands out the next tick of the synthetic pre-recording timeline —
    /// see `nextPreRecordingSampleOffset`'s doc comment.
    private func reservePreRecordingSampleOffset() -> Int64 {
        defer { nextPreRecordingSampleOffset += 1 }
        return nextPreRecordingSampleOffset
    }

    private func updateBlock(atLineIndex index: Int, text: String) async {
        guard let selfPersonID = environment.selfPersonID, var block = lines[index].block else { return }
        let now = environment.clock.now()
        block.content = .text(text)
        block.opLog.append(
            Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(text)))
        do {
            try await environment.noteBlockRepository.update(block, at: now)
            lines[index].block = block
        } catch {
            loadError = "\(error)"
        }
    }

    /// Restores any lines already written this session — the canvas can
    /// reappear (tab away and back) without losing what's on the page.
    private func loadExistingLines() async {
        guard let meetingID = session.meetingID else { return }
        do {
            let blocks = try await environment.noteBlockRepository.fetchAll(meetingID: meetingID)
            let richTextBlocks = blocks.filter { $0.type == .richText }.sorted {
                $0.creationRange.startSample < $1.creationRange.startSample
            }
            guard !richTextBlocks.isEmpty else { return }
            let sampleRate = await session.currentSampleRate() ?? 48000
            lines =
                richTextBlocks.map { block in
                    var line = PadNoteLine()
                    line.block = block
                    if case .text(let text) = block.content { line.text = text }
                    if block.creationRange.startSample < 0 {
                        line.timestampLabel = "--:--"
                    } else {
                        let seconds = Double(block.creationRange.startSample) / Double(max(sampleRate, 1))
                        line.timestampLabel = Self.formatElapsed(seconds)
                    }
                    return line
                } + [PadNoteLine()]
        } catch {
            loadError = "\(error)"
        }
    }

    private static func millisecondTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Ink
//
// Split into an extension (rather than staying in the struct body above) to
// stay under SwiftLint's type-body-length cap — `private` here still
// reaches every `@State` var declared in the struct, since both live in
// this same file.
extension PadRecordingCanvas {
    /// `PadInkCanvas` reports the whole drawing on every change; strokes
    /// past the count we last saw are the new ones (PencilKit only ever
    /// appends to `PKDrawing.strokes`), computed from the *previous*
    /// `drawing` before it's overwritten.
    private func handleDrawingChange(_ newDrawing: PKDrawing) {
        let previousCount = drawing.strokes.count
        drawing = newDrawing
        guard newDrawing.strokes.count > previousCount else { return }
        let newStrokes = Array(newDrawing.strokes[previousCount...])
        Task { await handleStrokesAdded(newStrokes) }
    }

    /// Feeds every newly-drawn stroke into `StrokeGroupTracker`, persisting
    /// whichever group closes as a result, and (re-)arms the idle-close
    /// timer so a group left open with no further strokes still gets
    /// stamped and saved rather than waiting forever for one more stroke.
    private func handleStrokesAdded(_ strokes: [PKStroke]) async {
        guard !strokes.isEmpty else { return }
        if strokeTracker == nil {
            let sampleRate = await session.currentSampleRate() ?? 48000
            strokeTracker = StrokeGroupTracker(sampleRate: sampleRate)
        }
        let isPreRecording = session.state == .draft
        let batchSampleOffset = isPreRecording ? nil : (await session.currentSampleOffset() ?? 0)
        for stroke in strokes {
            let strokeID = UUID()
            strokesByID[strokeID] = stroke
            let sampleOffset = batchSampleOffset ?? reservePreRecordingSampleOffset()
            let event = InkStrokeEvent(strokeID: strokeID, boundingBox: stroke.renderBounds, sampleOffset: sampleOffset)
            if let closedGroup = strokeTracker?.handle(event) {
                await persist(group: closedGroup)
            }
        }
        armIdleGroupCloseTimer()
    }

    private func armIdleGroupCloseTimer() {
        idleGroupCloseTask?.cancel()
        idleGroupCloseTask = Task {
            try? await Task.sleep(for: Self.idleGroupCloseDelay)
            guard !Task.isCancelled else { return }
            await closeOpenInkGroupIfNeeded()
        }
    }

    /// Force-closes whatever ink group is open — called by the idle timer,
    /// on tool switch away from Pen, on Stop, and when the canvas leaves
    /// the screen, so a group is never left unpersisted indefinitely.
    private func closeOpenInkGroupIfNeeded() async {
        idleGroupCloseTask?.cancel()
        idleGroupCloseTask = nil
        if let closedGroup = strokeTracker?.closeOpenGroup() {
            await persist(group: closedGroup)
        }
    }

    private func persist(group: InkStrokeGroup) async {
        guard let meetingID = session.meetingID, let selfPersonID = environment.selfPersonID,
            let container = session.meetingContainer
        else { return }
        let groupStrokes = group.strokeIDs.compactMap { strokesByID[$0] }
        for id in group.strokeIDs { strokesByID.removeValue(forKey: id) }
        guard !groupStrokes.isEmpty else { return }

        let filename = "\(UUID().uuidString).drawing"
        let relativePath = "ink/\(filename)"
        let assetURL = container.inkDirectoryURL.appendingPathComponent(filename)
        let now = environment.clock.now()

        do {
            let data = PKDrawing(strokes: groupStrokes).dataRepresentation()
            try environment.inkAssetFileSystem.write(data, to: assetURL)
            let content = BlockContent.assetReference(path: relativePath)
            let block = NoteBlock(
                blockID: NoteBlockID(rawValue: UUID()), meetingID: meetingID, authorID: selfPersonID, type: .sketch,
                content: content, creationRange: group.sampleRange, privacy: .shared,
                opLog: [
                    Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: content)
                ])
            try await environment.noteBlockRepository.insert(block, at: now)
        } catch {
            loadError = "\(error)"
        }
    }

    /// Restores every already-persisted `.sketch` block's strokes into one
    /// composited `PKDrawing` for display — each block keeps its own
    /// `creationRange` in the database; only strokes drawn *after* this
    /// load feed the tracker (`handleDrawingChange`'s count-diff already
    /// treats everything in the restored `drawing` as a fixed baseline).
    private func loadExistingInk() async {
        guard let meetingID = session.meetingID, let container = session.meetingContainer else { return }
        do {
            let blocks = try await environment.noteBlockRepository.fetchAll(meetingID: meetingID)
            let sketchBlocks = blocks.filter { $0.type == .sketch }
            var strokes: [PKStroke] = []
            for block in sketchBlocks {
                guard case .assetReference(let path) = block.content else { continue }
                let url = container.rootURL.appendingPathComponent(path)
                let data = try environment.inkAssetFileSystem.read(from: url)
                strokes.append(contentsOf: try PKDrawing(data: data).strokes)
            }
            drawing = PKDrawing(strokes: strokes)
        } catch {
            loadError = "\(error)"
        }
    }
}
