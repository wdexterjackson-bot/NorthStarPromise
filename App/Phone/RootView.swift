import SwiftUI

/// The five top-level tabs. Named separately from `TodayView`'s own type
/// so any screen can request a tab switch (Today's "See all" links to
/// Library/Actions) without depending on `RootView` itself.
enum AppTab: Hashable {
    case today, library, ask, actions, settings
}

/// The 5-tab structure docs/07 §1.1 assigns to iPhone: Today, Library, Ask,
/// Actions, Settings. Nothing else is a top-level destination (docs/07 §1).
@MainActor
struct RootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession
    @State private var selectedTab: AppTab = .today

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(environment: environment, session: recordingSession, selectTab: { selectedTab = $0 })
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

            LibraryView(environment: environment)
                .tabItem { Label("Library", systemImage: "list.bullet") }
                .tag(AppTab.library)

            AskView(environment: environment)
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppTab.ask)

            ActionsView(environment: environment)
                .tabItem { Label("Actions", systemImage: "checkmark.circle") }
                .tag(AppTab.actions)

            SettingsView(environment: environment)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
