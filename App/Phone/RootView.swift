import SwiftUI
import UIKit

/// The five top-level areas. Named separately from any one screen's type
/// so any view can request an area switch (Today's "See all" links to
/// Library/Actions) without depending on `RootView`/`PadRootView`
/// themselves.
enum AppTab: CaseIterable, Hashable {
    case today, library, ask, actions, settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .library: return "Library"
        case .ask: return "Ask"
        case .actions: return "Actions"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: return "sun.max"
        case .library: return "list.bullet"
        case .ask: return "bubble.left.and.text.bubble.right"
        case .actions: return "checkmark.circle"
        case .settings: return "gearshape"
        }
    }
}

/// Picks the iPhone tab bar or the iPad sidebar shell (docs/07 §1.1's
/// "expansion rule") by the actual device idiom — this app is universal
/// (`TARGETED_DEVICE_FAMILY: "1,2"`), not a separate iPad target, so the
/// choice is runtime, not build-time.
@MainActor
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            PadRootView(environment: environment)
        } else {
            PhoneRootView(environment: environment)
        }
    }
}

/// The 5-tab structure docs/07 §1.1 assigns to iPhone: Today, Library, Ask,
/// Actions, Settings. Nothing else is a top-level destination (docs/07 §1).
@MainActor
private struct PhoneRootView: View {
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
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbolName) }
                .tag(AppTab.today)

            LibraryView(environment: environment)
                .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.symbolName) }
                .tag(AppTab.library)

            AskView(environment: environment)
                .tabItem { Label(AppTab.ask.title, systemImage: AppTab.ask.symbolName) }
                .tag(AppTab.ask)

            ActionsView(environment: environment)
                .tabItem { Label(AppTab.actions.title, systemImage: AppTab.actions.symbolName) }
                .tag(AppTab.actions)

            SettingsView(environment: environment)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName) }
                .tag(AppTab.settings)
        }
    }
}
