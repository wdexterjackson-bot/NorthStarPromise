import NSPCore
import NSPDesignSystem
import SwiftUI

/// iPad's signature capability (docs/07 §5): a college-ruled notebook page
/// that appears the moment a meeting goes `Recording`. Recording controls
/// live in a fixed top toolbar; the page below is ruled lines with a
/// timestamp margin. The first character typed on a line stamps that
/// line's margin with elapsed time at that instant (`mm:ss`) — a new line
/// gets its own stamp only once it receives its own first character. Each
/// line is a real `.richText` `NoteBlock` anchored to the exact sample
/// offset it was started at (`RecordingSession.currentSampleOffset()`),
/// not the wall-clock label shown in the margin — the same "display uses
/// elapsed seconds, persistence uses the real sample offset" split
/// `SessionMarker` uses on iPhone.
///
/// Apple Pencil ink capture (stroke grouping into margin timestamps,
/// `docs/07 §5`) is a documented follow-up, not built in this pass — this
/// canvas is the typed-notes half of that spec.
@MainActor
struct PadRecordingCanvas: View {
    let environment: AppEnvironment
    let session: RecordingSession

    @State private var lines: [PadNoteLine] = [PadNoteLine()]
    @FocusState private var focusedLineID: UUID?
    @State private var isConfirmingStop = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
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
                .padding(.top, NSPSpacing.large)
            }
            .background(NSPColor.background)
        }
        .task { await loadExistingLines() }
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

    private var elapsedLabel: String {
        let totalSeconds = Int(session.elapsedSeconds)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    private var isPaused: Bool { session.state == .paused }

    private var toolbar: some View {
        HStack(spacing: NSPSpacing.large) {
            Text(elapsedLabel).font(.title2.monospacedDigit().weight(.bold))

            if isPaused {
                NSPStatusBadge(symbolName: "pause.circle.fill", label: "Paused", tint: NSPColor.statusWarning)
            } else {
                NSPStatusBadge(symbolName: "record.circle.fill", label: "Recording", tint: NSPColor.statusDanger)
            }

            NSPLevelMeter(level: session.inputLevel, segmentCount: 14).frame(width: 140)

            Spacer()

            Button {
                Task { await session.addMarker() }
            } label: {
                Label("Marker", systemImage: "flag")
            }
            .disabled(session.state != .recording)

            if isPaused {
                Button {
                    Task { await session.resume() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button {
                    Task { await session.pause() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            }

            Button(role: .destructive) {
                isConfirmingStop = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.bordered)
        .padding(NSPSpacing.medium)
        .background(NSPColor.cardBackground)
    }

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

    private static func millisecondTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
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

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// One ruled line's state: its text, the `NoteBlock` it's backed by (once
/// it has one), and the margin label to display.
struct PadNoteLine: Identifiable {
    let id = UUID()
    var text: String = ""
    var block: NoteBlock?
    var timestampLabel: String?
}

private struct PadNoteLineRow: View {
    @Binding var line: PadNoteLine
    var focusedLineID: FocusState<UUID?>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NSPSpacing.medium) {
            Text(line.timestampLabel ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(NSPColor.secondaryText)
                .frame(width: 52, alignment: .trailing)

            TextField("", text: $line.text)
                .font(.body)
                .focused(focusedLineID, equals: line.id)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
