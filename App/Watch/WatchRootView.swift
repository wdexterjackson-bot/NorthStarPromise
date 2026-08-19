import SwiftUI

/// Placeholder shell. Replaced by the Ready/Recording/Paused/Finalizing states
/// in NSP-026 (docs/07 §3).
struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "North-Star",
                systemImage: "waveform",
                description: Text("Watch capture lands in M1.")
            )
            .toolbar {
                // NSP-002 spike entry point — remove once the hardware spike report locks a
                // recording-affordance strategy and NSP-018/019 supersede it.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Spike") {
                        SpikeRecordingView()
                    }
                }
            }
        }
    }
}

#Preview {
    WatchRootView()
}
