import SwiftUI

/// NSP-002 measurement tool only — see `SpikeRecordingController` header comment.
struct SpikeRecordingView: View {
    @State private var controller = SpikeRecordingController()
    @State private var strategy: SpikeStrategy = .plainSession

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker("Strategy", selection: $strategy) {
                    ForEach(SpikeStrategy.allCases) { candidate in
                        Text(candidate.rawValue).tag(candidate)
                    }
                }
                .disabled(controller.isRecording)

                Text(formatted(controller.elapsed))
                    .font(.system(.title2, design: .monospaced))
                    .monospacedDigit()

                if controller.isRecording {
                    Button("Stop", role: .destructive) {
                        controller.stop()
                    }
                } else {
                    Button("Start") {
                        controller.start(strategy: strategy)
                    }
                }

                ShareLink(item: controller.exportText) {
                    Label("Export log", systemImage: "square.and.arrow.up")
                }
                .disabled(controller.logLines.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Spike")
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        return String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds / 60) % 60, totalSeconds % 60)
    }
}

#Preview {
    NavigationStack {
        SpikeRecordingView()
    }
}
