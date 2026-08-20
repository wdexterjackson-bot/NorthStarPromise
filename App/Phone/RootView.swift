import SwiftUI

/// The 5-tab structure docs/07 §1.1 assigns to iPhone: Today, Library, Ask,
/// Actions, Settings. Nothing else is a top-level destination (docs/07 §1).
@MainActor
struct RootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
    }

    var body: some View {
        TabView {
            TodayView(environment: environment, session: recordingSession)
                .tabItem { Label("Today", systemImage: "sun.max") }

            LibraryView(environment: environment)
                .tabItem { Label("Library", systemImage: "list.bullet") }

            AskView(environment: environment)
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }

            ActionsView(environment: environment)
                .tabItem { Label("Actions", systemImage: "checkmark.circle") }

            SettingsView(environment: environment)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
