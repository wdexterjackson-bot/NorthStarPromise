import NSPCore
import NSPDesignSystem
import NSPMedia
import PencilKit
import SwiftUI
import UIKit

/// The writing tool currently active on `PadRecordingCanvas` — shared with
/// `PadCanvasHeader`, which renders the palette that sets it.
enum PadTool: Equatable {
    case pointer, text, pen, highlighter
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
    // `loadError`, the ink `@State`, and the two helpers/constant just below
    // aren't `private` — `PadRecordingCanvas+Ink.swift` (a separate file,
    // split out to stay under SwiftLint's file-length cap) needs them, and
    // `private` doesn't cross files even between extensions of the same type.
    @State var loadError: String?
    @State private var activeTool: PadTool = .pointer
    @State private var meetingTitle = ""
    @State private var meetingSubtitle = ""
    @State private var penColor: Color = .black
    @State var drawing = PKDrawing()
    @State var strokesByID: [UUID: PKStroke] = [:]
    @State var strokeTracker: StrokeGroupTracker?
    @State var idleGroupCloseTask: Task<Void, Never>?
    /// A synthetic, all-negative sample timeline for content created before
    /// recording starts (`state == .draft`) — increases monotonically just
    /// like the real one, so ordering/grouping logic that compares sample
    /// offsets keeps working unmodified, but every value sorts before any
    /// real (non-negative) offset and is unambiguously "pre-recording" for
    /// the `--:--` margin stamp (docs/07 §5). Never persisted as a claim
    /// about real elapsed time — it just needs to be negative and ordered.
    @State var nextPreRecordingSampleOffset: Int64 = -1_000_000_000_000

    static let idleGroupCloseDelay: Duration = .seconds(2)

    var body: some View {
        VStack(spacing: 0) {
            PadCanvasHeader(
                session: session, activeTool: $activeTool, penColor: $penColor, isConfirmingStop: $isConfirmingStop,
                onSelectNonPenTool: {
                    focusedLineID = focusedLineID ?? lines.first?.id
                    Task { await closeOpenInkGroupIfNeeded() }
                })
            ZStack(alignment: .topLeading) {
                page
                PadInkCanvas(
                    drawing: $drawing, isActive: isInkToolActive, tool: currentInkTool,
                    onDrawingChanged: handleDrawingChange
                )
                .allowsHitTesting(isInkToolActive)
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

    private var isInkToolActive: Bool { activeTool == .pen || activeTool == .highlighter }

    /// The real `PKTool` for whichever writing tool is active — Selection
    /// and Text never draw, so a placeholder lasso tool is fine for them
    /// (hit-testing is already off in those states).
    private var currentInkTool: PKTool {
        switch activeTool {
        case .pen: return PKInkingTool(.pen, color: UIColor(penColor), width: 3)
        case .highlighter:
            return PKInkingTool(
                .marker, color: UIColor(PadCanvasHeader.highlighterColor).withAlphaComponent(0.4), width: 18)
        case .pointer, .text: return PKLassoTool()
        }
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            VStack(spacing: NSPSpacing.small) {
                TextField("Meeting name", text: $meetingTitle)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .onSubmit { Task { await saveMeetingTitle() } }
                TextField("Subtitle", text: $meetingSubtitle)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(NSPColor.secondaryText)
                    .onSubmit { Task { await saveMeetingSubtitle() } }
            }
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
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
            .background(alignment: .topLeading) { pageRules }
        }
        .background(Color.white)
        .onDisappear {
            Task {
                await saveMeetingTitle()
                await saveMeetingSubtitle()
            }
        }
    }

    /// The blue horizontal ruled lines + red vertical margin rule, matching
    /// the mockup — drawn once behind the whole page rather than per-row,
    /// so ruled lines cover the full sheet (not just rows with a typed
    /// `PadNoteLine` on them) and both rules grow automatically as the page
    /// grows past its `minHeight` (`Canvas`/`Rectangle` both read whatever
    /// size their container ends up being, every time it changes).
    private var pageRules: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                var ruleY = PadNoteLineRow.rowHeight
                while ruleY < size.height {
                    let line = Path { path in
                        path.move(to: CGPoint(x: 0, y: ruleY))
                        path.addLine(to: CGPoint(x: size.width, y: ruleY))
                    }
                    context.stroke(line, with: .color(.blue.opacity(0.25)), lineWidth: 1)
                    ruleY += PadNoteLineRow.rowHeight
                }
            }
            Rectangle()
                .fill(Color.red.opacity(0.55))
                .frame(width: 1.5)
                .padding(.leading, PadNoteLineRow.timestampGutterWidth + NSPSpacing.medium)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Meeting title

    private func loadMeetingTitle() async {
        guard let meetingID = session.meetingID, let meeting = try? await environment.meetingRepository.find(meetingID)
        else { return }
        meetingTitle = meeting.title
        meetingSubtitle = meeting.subtitle ?? ""
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

    private func saveMeetingSubtitle() async {
        guard let meetingID = session.meetingID,
            var meeting = try? await environment.meetingRepository.find(meetingID)
        else { return }
        let trimmed = meetingSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSubtitle = trimmed.isEmpty ? nil : trimmed
        guard newSubtitle != meeting.subtitle else { return }
        meeting.subtitle = newSubtitle
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
    func reservePreRecordingSampleOffset() -> Int64 {
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

    static func millisecondTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// Ink capture (stroke grouping, persistence, restore) lives in
// `PadRecordingCanvas+Ink.swift` — split out to stay under SwiftLint's
// file-length cap.
