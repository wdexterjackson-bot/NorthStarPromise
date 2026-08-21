import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// iPad's information architecture: a persistent top header carrying the
/// app's primary areas (`Self.headerAreas` — Dashboard, Today, Library,
/// Ask, Projects, Settings), a left panel that's Dashboard-specific
/// (`PadDashboardSidebar`, its own restricted nav list of Actions, Threads,
/// People, Calendar plus the agenda and capture control — reverted here
/// after a fuller-header version didn't feel right), and a detail column
/// for the selected meeting — the ruled-paper canvas (`PadRecordingCanvas`)
/// while it's the meeting currently recording, the same `MeetingDetailView`
/// tabs iPhone uses once it isn't.
@MainActor
struct PadRootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession
    // `content` falls back to `.dashboard` whenever this is `nil`. `.today`
    // is still a valid value — Dashboard's "Open Today" card sets it
    // directly — it's just excluded from `areaSwitcher`'s visible segments
    // (`AppTab.visibleCases`'s doc comment).
    @State private var selectedArea: AppTab? = .dashboard
    @State private var selectedMeetingID: MeetingID?
    /// `.detailOnly` while drafting/recording (`isRecordingSelectedMeeting`)
    /// — the ruled-paper canvas takes the full window width with no area
    /// switcher competing for space; `.all` otherwise. Starting from `.all`
    /// rather than `.automatic` matters: for a plain two-column split,
    /// `.automatic` collapses the leading column away by default on this
    /// size class — exactly the area-switcher-and-content column this pass
    /// is trying to keep permanently visible, not turn into a togglable
    /// sidebar.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Shared between `PadDashboardSidebar`'s agenda/nav-counts and
    /// `PadDashboardMainColumn`'s hero/sections — loaded once here rather
    /// than duplicated by each half (`DashboardComposer`'s own doc comment:
    /// cheap, but still real repository reads).
    @State private var dashboardModel: DashboardModel?
    /// Drives `DASHBOARD_SPEC.md` §4.7's width breakpoint: 280pt sidebar and
    /// a 2-column/top-2 "Threads in motion" below 1000pt (11" portrait),
    /// 304pt and 3 columns at or above it.
    @State private var windowWidth: CGFloat = 1024
    private var isCompactPadWidth: Bool { windowWidth < 1000 }
    @State private var isShowingAudioImportPicker = false
    @State private var isShowingAddAgendaItem = false

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
    }

    /// Whether `selectedMeetingID` is the meeting `recordingSession` owns
    /// right now — either actively capturing, or a pre-recording draft
    /// (docs/07 §5) — the cases where the detail column shows the
    /// ruled-paper canvas instead of the regular tabbed detail.
    private var isRecordingSelectedMeeting: Bool {
        guard let selectedMeetingID, selectedMeetingID == recordingSession.meetingID else { return false }
        return recordingSession.state == .recording || recordingSession.state == .paused
            || recordingSession.state == .arming || recordingSession.state == .draft
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isRecordingSelectedMeeting {
                topHeaderBar
            }
            NavigationSplitView(columnVisibility: $columnVisibility) {
                leadingColumn
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in windowWidth = newValue }
            }
        )
        // A new recording jumps the detail column to its canvas
        // automatically — the whole point of starting on iPad is to write
        // while it records, not to hunt for the meeting afterward.
        .onChange(of: recordingSession.meetingID) { _, newValue in
            if let newValue { selectedMeetingID = newValue }
        }
        .onChange(of: isRecordingSelectedMeeting) { _, isRecording in
            columnVisibility = isRecording ? .detailOnly : .all
        }
        // `MeetingDetailView` is never pushed or presented here — it's the
        // detail column's direct content — so its own `dismiss()` reaction
        // to a delete has no effect on this layout. Clearing the selection
        // is what makes the column fall back to its empty-state placeholder
        // instead of continuing to render the deleted meeting.
        .onChange(of: environment.lastDeletedMeetingID) { _, deletedID in
            if deletedID == selectedMeetingID { selectedMeetingID = nil }
        }
        // Same late-binding as `PhoneRootView` — see
        // `ScheduledRecordingCoordinator.activeSession`'s doc comment.
        .task { environment.scheduledRecordingCoordinator.activeSession = recordingSession }
        .onChange(of: recordingSession.state) { _, newState in
            environment.scheduledRecordingCoordinator.recordingStateChanged(newState)
        }
        // Moved here from `TodayView` — see `PhoneRootView`'s identical
        // modifier for why (Today is no longer permanently mounted).
        .modifier(
            TodayPromptSheets(
                session: recordingSession, environment: environment,
                onDismiss: { environment.bumpContentRevision() })
        )
        .modifier(IntelligenceStatusOverlay(environment: environment))
        .task { await loadDashboardModel() }
        .onChange(of: environment.contentRevision) { _, _ in Task { await loadDashboardModel() } }
        .audioImportSheets(
            isShowingPicker: $isShowingAudioImportPicker, environment: environment,
            onDone: { Task { await loadDashboardModel() } }
        )
        .sheet(isPresented: $isShowingAddAgendaItem) {
            AddAgendaItemFormView(environment: environment, onDone: { Task { await loadDashboardModel() } })
        }
    }

    private func loadDashboardModel() async {
        dashboardModel = try? await environment.composeDashboard()
    }

    @ViewBuilder
    private var leadingColumn: some View {
        if (selectedArea ?? .dashboard) == .dashboard {
            PadDashboardSidebar(
                model: dashboardModel, selectedArea: selectedArea ?? .dashboard, width: isCompactPadWidth ? 280 : 304,
                onSelectArea: { selectedArea = $0 }, onSelectMeeting: { selectedMeetingID = $0 },
                onRecall: { selectedArea = .ask },
                onStartMeeting: {
                    Task { await recordingSession.start() }
                    selectedArea = .today
                },
                onStartNotesOnly: {
                    Task { await recordingSession.startStandaloneNote() }
                    selectedArea = .today
                },
                onStartMentalNote: {
                    Task { await recordingSession.startBrainDump() }
                    selectedArea = .today
                }, onImportAudio: { isShowingAudioImportPicker = true },
                onAddAgendaItem: { isShowingAddAgendaItem = true })
        } else {
            content.navigationTitle("North-Star Promise")
        }
    }

    /// Only these six — Actions/Threads/People/Calendar moved to
    /// `PadDashboardSidebar`'s own restricted nav list instead (this
    /// header briefly carried all 8 `AppTab.visibleCases`; reverted after
    /// that read as too much in one bar).
    private static let headerAreas: [AppTab] = [.dashboard, .today, .library, .ask, .projects, .settings]

    /// The persistent, full-width top header — hidden only while
    /// `isRecordingSelectedMeeting` (recording or pre-recording
    /// note-taking), since the ruled-paper canvas takes the full window at
    /// that point and area-switching mid-session isn't a real use case.
    private var topHeaderBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: NSPSpacing.small) {
                ForEach(Self.headerAreas, id: \.self) { area in
                    let isSelected = (selectedArea ?? .dashboard) == area
                    Button {
                        selectedArea = area
                    } label: {
                        Label(area.title, systemImage: area.symbolName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                            .padding(.horizontal, NSPSpacing.medium)
                            .padding(.vertical, NSPSpacing.small)
                            .background(isSelected ? Palette.accent.foreground : Palette.fill, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NSPSpacing.large)
        .padding(.vertical, NSPSpacing.small)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedArea ?? .dashboard {
        case .dashboard:
            DashboardView(
                environment: environment, session: recordingSession, selectTab: { selectedArea = $0 },
                onSelectMeeting: { selectedMeetingID = $0 }, onOpenToday: { selectedArea = .today })
        case .today:
            TodayView(
                environment: environment, session: recordingSession, selectTab: { selectedArea = $0 },
                onSelectMeeting: { selectedMeetingID = $0 })
        case .library:
            LibraryView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .ask:
            AskView(environment: environment)
        case .actions:
            ActionsView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .projects:
            ProjectsListView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .people:
            PeopleListView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .threads:
            ThreadsListView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .settings:
            SettingsView(environment: environment)
        case .calendar:
            CalendarView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedMeetingID {
            if isRecordingSelectedMeeting {
                PadRecordingCanvas(environment: environment, session: recordingSession)
            } else {
                MeetingDetailView(meetingID: selectedMeetingID, environment: environment)
            }
        } else if (selectedArea ?? .dashboard) == .dashboard {
            PadDashboardMainColumn(
                model: dashboardModel, isCompactWidth: isCompactPadWidth, onSelectMeeting: { selectedMeetingID = $0 },
                onSelectArea: { selectedArea = $0 })
        } else {
            ContentUnavailableView(
                "Select a meeting", systemImage: "person.2",
                description: Text("Choose a meeting from Today or Library to see it here."))
        }
    }
}
