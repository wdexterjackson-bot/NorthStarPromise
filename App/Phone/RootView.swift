import SwiftUI

/// Placeholder shell. Replaced by the Today screen in NSP-037 (docs/07 §4).
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "North-Star Promise",
            systemImage: "waveform",
            description: Text("Vertical slice lands in M1 — see docs/08-MILESTONES.md.")
        )
    }
}

#Preview {
    RootView()
}
