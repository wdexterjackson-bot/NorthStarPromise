import NSPDesignSystem
import SwiftUI

/// The dark, single-row header from the reference mockup (docs/07 §5,
/// `~/Downloads/IMG_0121.PNG`): transport controls on the left, a centered
/// tool palette, utility icons on the right — all one row, icon-only.
/// Selection/Text/Pen/Highlighter are real; Camera/Share/New page/Settings
/// and the skip/play scrub controls are drawn to match the mockup's shape
/// but are honestly disabled — see `PadRecordingCanvas`'s type doc comment
/// for what's not built yet (playback scrubbing, photo insertion).
struct PadCanvasHeader: View {
    let session: RecordingSession
    @Binding var activeTool: PadTool
    @Binding var penColor: Color
    @Binding var isConfirmingStop: Bool
    var onSelectNonPenTool: () -> Void

    /// Fixed, not user-chosen — the mockup shows exactly one highlighter
    /// colour, unlike pen's black/green choice.
    static let highlighterColor = Color.yellow

    private static let backgroundColor = Color(red: 0.06, green: 0.12, blue: 0.28)
    private static let penColorChoices: [Color] = [.black, .green]

    private var isPaused: Bool { session.state == .paused }
    private var isDrafting: Bool { session.state == .draft }
    private var isRecording: Bool { session.state == .recording }

    private var elapsedLabel: String {
        let totalSeconds = Int(session.elapsedSeconds)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    var body: some View {
        ZStack {
            HStack(spacing: NSPSpacing.large) {
                transportControls
                Spacer(minLength: NSPSpacing.large)
                utilityIcons
            }
            toolPalette
        }
        .padding(NSPSpacing.medium)
        .background(Self.backgroundColor)
    }

    // MARK: - Transport

    /// One row across every state (docs/07 §5's mockup shows the same
    /// transport icons pre-recording as while recording): the record
    /// control switches meaning with `session.state`; Marker and Stop
    /// only make sense once actually recording; elapsed time and the
    /// level meter only have anything to show then either.
    private var transportControls: some View {
        HStack(spacing: NSPSpacing.medium) {
            if isRecording || isPaused {
                Text(elapsedLabel)
                    .font(Typo.ui(13, .extrabold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                NSPLevelMeter(level: session.inputLevel, segmentCount: 10).frame(width: 90)
            }

            recordButton

            if isRecording || isPaused {
                iconButton(symbol: "stop.fill", tint: Palette.danger.foreground) { isConfirmingStop = true }
                iconButton(symbol: "flag", isEnabled: isRecording) { Task { await session.addMarker() } }
            }

            // Scrub already-recorded audio without leaving the page
            // (docs/07 §5) — not built yet, shown to match the mockup's
            // shape rather than hidden.
            disabledIcon(symbol: "gobackward.10")
            disabledIcon(symbol: "play.fill")
            disabledIcon(symbol: "goforward.10")
        }
    }

    private var recordButton: some View {
        Group {
            if isDrafting {
                iconButton(symbol: "record.circle", tint: Palette.danger.foreground) { Task { await session.start() } }
            } else if isPaused {
                iconButton(symbol: "play.circle.fill", tint: .white) { Task { await session.resume() } }
            } else {
                iconButton(symbol: "pause.circle.fill", tint: .white) { Task { await session.pause() } }
            }
        }
    }

    // MARK: - Tool palette

    private var toolPalette: some View {
        HStack(spacing: NSPSpacing.medium) {
            toolButton(.pointer, symbol: "cursorarrow")
            toolButton(.text, symbol: "character.cursor.ibeam")
            toolButton(.pen, symbol: "pencil.tip")
            if activeTool == .pen {
                penColorSwatch
            }
            toolButton(.highlighter, symbol: "highlighter", tint: Self.highlighterColor)
            disabledIcon(symbol: "camera")
        }
    }

    private var penColorSwatch: some View {
        Menu {
            ForEach(Self.penColorChoices, id: \.self) { color in
                Button {
                    penColor = color
                } label: {
                    Label(color == .black ? "Black" : "Green", systemImage: "circle.fill")
                }
            }
        } label: {
            Circle().fill(penColor).frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
        }
    }

    private func toolButton(_ tool: PadTool, symbol: String, tint: Color = .white) -> some View {
        Button {
            activeTool = tool
            if tool != .pen, tool != .highlighter { onSelectNonPenTool() }
        } label: {
            Image(systemName: symbol)
                .font(Typo.ui(14, .bold))
                .foregroundStyle(activeTool == tool ? Self.backgroundColor : tint)
                .frame(width: 36, height: 32)
                .background(activeTool == tool ? Color.white : Color.white.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }

    // MARK: - Utility

    private var utilityIcons: some View {
        HStack(spacing: NSPSpacing.medium) {
            disabledIcon(symbol: "square.and.arrow.up")
            disabledIcon(symbol: "doc.badge.plus")
            disabledIcon(symbol: "wrench")
        }
    }

    private func iconButton(
        symbol: String, tint: Color = .white, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typo.ui(17, .bold))
                .foregroundStyle(isEnabled ? tint : tint.opacity(0.35))
        }
        .disabled(!isEnabled)
    }

    /// Present so the header matches the mockup's shape, but honestly
    /// inert — never a control that looks live and silently does nothing.
    private func disabledIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(Typo.ui(17, .bold))
            .foregroundStyle(.white.opacity(0.3))
    }
}
