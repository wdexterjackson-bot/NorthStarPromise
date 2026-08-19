import SwiftUI

/// Placeholder shell. Replaced by the Ready/Recording/Paused/Finalizing states
/// in NSP-026 (docs/07 §3).
struct WatchRootView: View {
    var body: some View {
        ContentUnavailableView(
            "North-Star",
            systemImage: "waveform",
            description: Text("Watch capture lands in M1.")
        )
    }
}

#Preview {
    WatchRootView()
}
