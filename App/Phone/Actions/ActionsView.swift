import SwiftUI

/// docs/07 §4's Actions dashboard: grouped by status
/// (`Proposed`/`Confirmed`/`Sent`/`InProgress`/`Done`/`Dismissed`).
/// `NSPActions` isn't wired to any screen yet — nothing extracts actions
/// from a meeting in this pass — so this is a correct, explicit empty
/// state rather than a fabricated ledger.
@MainActor
struct ActionsView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No actions yet", systemImage: "checkmark.circle",
                description: Text("Actions extracted from your meetings will appear here, grouped by status.")
            )
            .navigationTitle("Actions")
        }
    }
}
