import NSPDesignSystem
import SwiftUI

/// The dark two-row header from the reference mockup (docs/07 §5): row 1
/// is real, functional recording controls (elapsed time, level meter,
/// Marker/Pause/Stop); row 2 is the writing-tool palette. Pointer/Text/Pen
/// are real; Highlighter/Camera/Share/New page/Settings are drawn to match
/// the mockup's shape but are honestly disabled — see `PadRecordingCanvas`'s
/// type doc comment for what's not built yet.
struct PadCanvasHeader: View {
    let session: RecordingSession
    @Binding var activeTool: PadTool
    @Binding var isConfirmingStop: Bool
    var onSelectNonPenTool: () -> Void

    private static let backgroundColor = Color(red: 0.06, green: 0.12, blue: 0.28)

    private var elapsedLabel: String {
        let totalSeconds = Int(session.elapsedSeconds)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    private var isPaused: Bool { session.state == .paused }

    var body: some View {
        VStack(spacing: NSPSpacing.small) {
            recordingControls
            toolPalette
        }
        .padding(NSPSpacing.medium)
        .background(Self.backgroundColor)
    }

    private var recordingControls: some View {
        HStack(spacing: NSPSpacing.large) {
            Text(elapsedLabel)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)

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
        .tint(.white)
    }

    private var toolPalette: some View {
        HStack(spacing: NSPSpacing.medium) {
            toolButton(.pointer, symbol: "cursorarrow")
            toolButton(.text, symbol: "character.cursor.ibeam")
            toolButton(.pen, symbol: "pencil.tip")
            disabledToolButton(symbol: "highlighter")
            disabledToolButton(symbol: "camera")

            Spacer()

            disabledToolButton(symbol: "square.and.arrow.up")
            disabledToolButton(symbol: "doc.badge.plus")
            disabledToolButton(symbol: "gearshape")
        }
    }

    private func toolButton(_ tool: PadTool, symbol: String) -> some View {
        Button {
            activeTool = tool
            if tool != .pen { onSelectNonPenTool() }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(activeTool == tool ? Self.backgroundColor : .white)
                .frame(width: 36, height: 32)
                .background(activeTool == tool ? Color.white : Color.white.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }

    /// Present so the palette matches the mockup's shape, but honestly
    /// inert — never a button that looks live and silently does nothing.
    private func disabledToolButton(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white.opacity(0.3))
            .frame(width: 36, height: 32)
    }
}
