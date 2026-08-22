import SwiftUI
import UIKit

/// The top-level areas. Named separately from any one screen's type so any
/// view can request an area switch (Dashboard's "See all" links to
/// Library/Actions/Projects) without depending on `RootView`/`PadRootView`
/// themselves. `.today` is deliberately not a direct tab-bar/area-switcher
/// destination — Dashboard replaced it as the first, default area; Today
/// is still a real destination, just reached by explicitly opening it from
/// Dashboard's "Today" card. Every other case gets a real `Tab` entry on
/// iPhone (`PhoneRootView`) — iOS 18's `Tab`/`.tabViewCustomization` API
/// supplies the "More" overflow and drag-to-rearrange behavior natively
/// once there are more tabs than fit the bar, so there's no hand-built
/// More screen to maintain.
enum AppTab: CaseIterable, Hashable {
    case myWork, dashboard, today, library, ask, actions, projects, people, threads, settings, calendar

    /// Every area with its own tab-bar/area-switcher entry — everything
    /// except `.today`.
    static var visibleCases: [AppTab] { allCases.filter { $0 != .today } }

    var title: String {
        switch self {
        case .myWork: return "My Work"
        case .dashboard: return "Dashboard"
        case .today: return "Today"
        case .library: return "Library"
        case .ask: return "Ask"
        case .actions: return "Actions"
        case .projects: return "Projects"
        case .people: return "People"
        case .threads: return "Threads"
        case .settings: return "Settings"
        case .calendar: return "Calendar"
        }
    }

    var symbolName: String {
        switch self {
        case .myWork: return "list.bullet.clipboard"
        case .dashboard: return "square.grid.2x2.fill"
        case .today: return "sun.max"
        case .library: return "list.bullet"
        case .ask: return "bubble.left.and.text.bubble.right"
        case .actions: return "checkmark.circle"
        case .projects: return "folder.fill"
        case .people: return "person.2.fill"
        case .threads: return "arrow.triangle.branch"
        case .settings: return "gearshape"
        case .calendar: return "calendar"
        }
    }
}

/// Settings' explicit appearance override (`AppEnvironment.appearanceMode`'s
/// own doc comment). `.system` maps to `nil` for `.preferredColorScheme`,
/// meaning "no override — follow the OS," which is also this app's default.
public enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
    /// Drives `DASHBOARD_SPEC.md` §4.7's compact-width rule: Slide Over and
    /// ⅓ Split View report `.compact` even on iPad, and the spec's own
    /// instruction there is to collapse to the iPhone layout rather than
    /// cram the sidebar shell into that width.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isShowingGettingStarted = false

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact {
                PadRootView(environment: environment)
            } else {
                PhoneRootView(environment: environment)
            }
        }
        // Applied once, above both shells, so a picked theme overrides the
        // OS setting everywhere in the app rather than screen-by-screen
        // (`AppEnvironment.appearanceMode`'s own doc comment).
        .preferredColorScheme(environment.appearanceMode.colorScheme)
        // "The First Hour" wizard auto-presents exactly once, only from
        // `.notStarted` (`OnboardingState.shouldAutoPresent`) — strictly
        // after the mandatory legal disclosure and permission sequence
        // (docs/06 §3.1, docs/07 §12), which both happen before `RootView`
        // ever mounts. Fully skippable and reachable again from Settings.
        .task {
            if environment.featureFlagProvider.isEnabled(.gettingStartedWizard),
                environment.defaultPolicy?.onboardingState.shouldAutoPresent == true
            {
                isShowingGettingStarted = true
            }
        }
        .fullScreenCover(isPresented: $isShowingGettingStarted) {
            GettingStartedWizardView(environment: environment, onDone: { isShowingGettingStarted = false })
        }
    }
}

/// The 6-tab structure on iPhone: Dashboard, Library, Ask, Actions,
/// Projects, Settings. Only 4-5 fit the bar at once — iOS 18's native
/// `Tab`/`.tabViewCustomization` puts the rest behind an automatically
/// generated "More" tab, and its own Edit affordance lets the user drag
/// tabs between the visible bar and More (exactly the platform's own
/// App Store-style tab customization, not a bespoke screen this app has to
/// maintain). The chosen arrangement persists across launches via
/// `tabCustomization`/`Self.customizationKey`.
@MainActor
private struct PhoneRootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession
    @State private var selectedTab: AppTab = .myWork
    @State private var tabCustomization: TabViewCustomization

    private static let customizationKey = "com.dexterjackson.northstarpromise.tabCustomization"

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
        self._tabCustomization = State(initialValue: Self.loadCustomization())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.myWork.title, systemImage: AppTab.myWork.symbolName, value: AppTab.myWork) {
                MyWorkView(environment: environment)
            }
            .customizationID("tab.myWork")

            Tab(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbolName, value: AppTab.dashboard) {
                DashboardView(environment: environment, session: recordingSession, selectTab: { selectedTab = $0 })
            }
            .customizationID("tab.dashboard")

            Tab(AppTab.library.title, systemImage: AppTab.library.symbolName, value: AppTab.library) {
                LibraryView(environment: environment)
            }
            .customizationID("tab.library")

            Tab(AppTab.ask.title, systemImage: AppTab.ask.symbolName, value: AppTab.ask) {
                AskView(environment: environment)
            }
            .customizationID("tab.ask")

            Tab(AppTab.actions.title, systemImage: AppTab.actions.symbolName, value: AppTab.actions) {
                ActionsView(environment: environment)
            }
            .customizationID("tab.actions")

            Tab(AppTab.projects.title, systemImage: AppTab.projects.symbolName, value: AppTab.projects) {
                ProjectsListView(environment: environment)
            }
            .customizationID("tab.projects")

            Tab(AppTab.people.title, systemImage: AppTab.people.symbolName, value: AppTab.people) {
                PeopleListView(environment: environment)
            }
            .customizationID("tab.people")

            Tab(AppTab.threads.title, systemImage: AppTab.threads.symbolName, value: AppTab.threads) {
                ThreadsListView(environment: environment)
            }
            .customizationID("tab.threads")

            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbolName, value: AppTab.settings) {
                SettingsView(environment: environment)
            }
            .customizationID("tab.settings")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .onChange(of: tabCustomization) { _, newValue in Self.saveCustomization(newValue) }
        // Late-bound rather than passed at `RecordingSession`'s own init —
        // `ScheduledRecordingCoordinator` is constructed in `AppEnvironment`,
        // before this view (and so the session) exists at all
        // (`ScheduledRecordingCoordinator.activeSession`'s doc comment).
        .task { environment.scheduledRecordingCoordinator.activeSession = recordingSession }
        .onChange(of: recordingSession.state) { _, newState in
            environment.scheduledRecordingCoordinator.recordingStateChanged(newState)
        }
        // Moved here from `TodayView` — Today is no longer a permanently
        // mounted tab, so the post-recording prompts need to live somewhere
        // that's alive regardless of which tab is active when a recording
        // stops (`TodayPromptSheets`' own doc comment covers why they exist
        // at all). `onDismiss` no longer has a single owning screen's
        // `load()` to call directly, so it bumps the shared revision both
        // `DashboardView` and `TodayView` watch instead
        // (`AppEnvironment.bumpContentRevision`'s doc comment).
        .modifier(
            TodayPromptSheets(
                session: recordingSession, environment: environment,
                onDismiss: { environment.bumpContentRevision() })
        )
        .modifier(IntelligenceStatusOverlay(environment: environment))
    }

    private static func loadCustomization() -> TabViewCustomization {
        guard let data = UserDefaults.standard.data(forKey: Self.customizationKey),
            let decoded = try? JSONDecoder().decode(TabViewCustomization.self, from: data)
        else { return TabViewCustomization() }
        return decoded
    }

    private static func saveCustomization(_ value: TabViewCustomization) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.customizationKey)
    }
}
