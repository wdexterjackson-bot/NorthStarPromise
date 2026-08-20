import NSPCore
import NSPDesignSystem
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
/// Scope of this pass, honestly: one page's worth of ink as a single
/// `.sketch` block (not per-stroke-group timestamps — `NOT-002`'s
/// grouping tolerance is a follow-up), no photo insertion, no
/// highlighter, no multi-page. Pre-recording availability (the canvas
/// showing before the user taps Record, with `--:--` stamps) also isn't
/// built — this pass only covers the already-recording case, since that's
/// the state `PadRootView` currently routes here for.
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
    @State private var inkBlock: NoteBlock?
    @State private var inkSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            PadCanvasHeader(
                session: session, activeTool: $activeTool, isConfirmingStop: $isConfirmingStop,
                onSelectNonPenTool: { focusedLineID = focusedLineID ?? lines.first?.id })
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
        .confirmationDialog(
            "Stop recording?", isPresented: $isConfirmingStop, titleVisibility: .visible
        ) {
            Button("Stop Recording", role: .destructive) {
                Task { await session.stop() }
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
        let sampleOffset = await session.currentSampleOffset() ?? 0
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
            lines[index].timestampLabel = Self.formatElapsed(session.elapsedSeconds)
        } catch {
            loadError = "\(error)"
        }
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
                    let seconds = Double(block.creationRange.startSample) / Double(max(sampleRate, 1))
                    line.timestampLabel = Self.formatElapsed(seconds)
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

    // MARK: - Ink

    private static let inkFileName = "page.drawing"
    private static let inkRelativePath = "ink/page.drawing"

    private func handleDrawingChange(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        inkSaveTask?.cancel()
        inkSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await saveInk(newDrawing)
        }
    }

    private func saveInk(_ drawing: PKDrawing) async {
        guard let meetingID = session.meetingID, let selfPersonID = environment.selfPersonID else { return }
        do {
            let container = try environment.makeMeetingContainer(meetingID: meetingID)
            let fileURL = container.inkDirectoryURL.appendingPathComponent(Self.inkFileName)
            try drawing.dataRepresentation().write(to: fileURL, options: .atomic)

            if let existing = inkBlock {
                try await environment.noteBlockRepository.update(existing, at: environment.clock.now())
            } else {
                let sampleOffset = await session.currentSampleOffset() ?? 0
                let now = environment.clock.now()
                let content = BlockContent.assetReference(path: Self.inkRelativePath)
                let block = NoteBlock(
                    blockID: NoteBlockID(rawValue: UUID()), meetingID: meetingID, authorID: selfPersonID, type: .sketch,
                    content: content, creationRange: SampleRange(startSample: sampleOffset, endSample: sampleOffset),
                    privacy: .shared,
                    opLog: [
                        Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: content)
                    ]
                )
                try await environment.noteBlockRepository.insert(block, at: now)
                inkBlock = block
            }
        } catch {
            loadError = "\(error)"
        }
    }

    private func loadExistingInk() async {
        guard let meetingID = session.meetingID else { return }
        do {
            let blocks = try await environment.noteBlockRepository.fetchAll(meetingID: meetingID)
            guard let block = blocks.first(where: { $0.type == .sketch }) else { return }
            inkBlock = block
            guard case .assetReference(let path) = block.content else { return }
            let container = try environment.makeMeetingContainer(meetingID: meetingID)
            let fileURL = container.rootURL.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: fileURL) else { return }
            drawing = try PKDrawing(data: data)
        } catch {
            loadError = "\(error)"
        }
    }
}
