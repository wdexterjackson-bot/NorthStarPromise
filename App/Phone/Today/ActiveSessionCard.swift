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

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            HStack {
                Text(elapsedLabel)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Spacer()
                if session.state == .paused {
                    NSPStatusBadge(symbolName: "pause.circle.fill", label: "Paused", tint: NSPColor.statusWarning)
                } else {
                    NSPStatusBadge(symbolName: "record.circle.fill", label: "Recording", tint: NSPColor.statusDanger)
                }
            }

            Text("Recording on this iPhone")
                .font(.caption)
                .foregroundStyle(NSPColor.secondaryText)

            if session.markerCount > 0 {
                Label("\(session.markerCount) marker\(session.markerCount == 1 ? "" : "s")", systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(NSPColor.secondaryText)
            }

            HStack(spacing: NSPSpacing.large) {
                Button {
                    Task { await session.addMarker() }
                } label: {
                    Label("Marker", systemImage: "flag")
                }
                .disabled(session.state != .recording)

                if session.state == .paused {
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

                Spacer()

                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, NSPSpacing.small)
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
