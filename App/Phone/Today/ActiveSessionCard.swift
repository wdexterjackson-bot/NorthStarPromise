import NSPDesignSystem
import SwiftUI

/// docs/07 §4's "Active session view": elapsed time, Marker/Pause/Stop,
/// capture-device attribution, and a processing-mode chip. The
/// "waveform-free level meter" and live provisional transcript from the
/// same spec paragraph aren't wired to any data source yet — omitted
/// rather than faked (docs/07 §11).
@MainActor
struct ActiveSessionCard: View {
    let session: RecordingSession
    @State private var isConfirmingStop = false

    private var elapsedLabel: String {
        let totalSeconds = Int(session.elapsedSeconds)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    private var isPaused: Bool { session.state == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            HStack {
                Circle()
                    .fill(isPaused ? NSPColor.statusWarning : NSPColor.statusDanger)
                    .frame(width: 10, height: 10)
                    .opacity(isPaused ? 1 : 0.9)
                Text(elapsedLabel)
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.bold))
                Spacer()
                if isPaused {
                    NSPStatusBadge(symbolName: "pause.circle.fill", label: "Paused", tint: NSPColor.statusWarning)
                } else {
                    NSPStatusBadge(symbolName: "record.circle.fill", label: "Recording", tint: NSPColor.statusDanger)
                }
            }

            HStack(spacing: NSPSpacing.medium) {
                Label("Recording on this iPhone", systemImage: "iphone")
                if session.markerCount > 0 {
                    Label(
                        "\(session.markerCount) marker\(session.markerCount == 1 ? "" : "s")", systemImage: "flag.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(NSPColor.secondaryText)

            HStack(spacing: NSPSpacing.medium) {
                Button {
                    Task { await session.addMarker() }
                } label: {
                    Label("Marker", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .disabled(session.state != .recording)

                if isPaused {
                    Button {
                        Task { await session.resume() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        Task { await session.pause() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .nspCard()
        // docs/07 §3.3/§4: stop requires a short confirmation, no hidden
        // gesture — the same rule the Watch's Stop button follows.
        .confirmationDialog(
            "Stop recording?", isPresented: $isConfirmingStop, titleVisibility: .visible
        ) {
            Button("Stop Recording", role: .destructive) {
                Task { await session.stop() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
