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
    @State private var selectedArea: AppTab? = .myWork
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
    /// Today's pending Scheduled Recordings, fed to `PadDashboardSidebar`
    /// alongside `dashboardModel.agenda` — see that view's own doc comment
    /// on `scheduledRecordings`.
    @State private var scheduledRecordings: [ScheduledRecording] = []
    /// A recurring series' future dates with no real row yet, today's
    /// window only — `RecurringOccurrenceExpansion`'s output (NSP-160).
    @State private var virtualOccurrences: [VirtualOccurrence] = []
    /// Today's due-dated, no-meeting `Action`s — "Action Reminder"'s
    /// collapsed home ("The Spine" recommendation, 2026-08-22).
    @State private var reminderActions: [Action] = []
    /// Drives `DASHBOARD_SPEC.md` §4.7's width breakpoint: 280pt sidebar and
    /// a 2-column/top-2 "Threads in motion" below 1000pt (11" portrait),
    /// 304pt and 3 columns at or above it.
    @State private var windowWidth: CGFloat = 1024
    private var isCompactPadWidth: Bool { windowWidth < 1000 }
    @State private var isShowingAudioImportPicker = false
    @State private var agendaSheet: AgendaSheet?

    /// Drives the single `AddAgendaItemFormView` sheet for both the "+"
    /// create flow and the agenda row "…" menu's "Modify Event" — `id`
    /// keyed so switching from one edit target to another (or from create
    /// to edit) always presents a fresh sheet instead of SwiftUI reusing
    /// stale `@State` from the previous target.
    private enum AgendaSheet: Identifiable {
        case create
        case editScheduledRecording(ScheduledRecording)
        case editMeeting(Meeting)
        case editReminderAction(Action)

        var id: String {
            switch self {
            case .create: return "create"
            case .editScheduledRecording(let item): return "s-\(item.scheduledRecordingID)"
            case .editMeeting(let meeting): return "m-\(meeting.meetingID)"
            case .editReminderAction(let action): return "r-\(action.actionID)"
            }
        }
    }

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

    /// A Brain Dump or standalone Note recording is active — same owner-
    /// agnostic `RecordingSession.State` check as `isRecordingSelectedMeeting`,
    /// but keyed off `brainDumpID`/`noteID` instead of a selected
    /// `MeetingID`, since neither of those owners has a "selection" concept
    /// to browse away from (NSP-155 — this was previously invisible on
    /// iPad: the detail column fell through to the Dashboard main column or
    /// an empty placeholder even while actively recording).
    private var isRecordingActiveSession: Bool {
        guard recordingSession.brainDumpID != nil || recordingSession.noteID != nil else { return false }
        return recordingSession.state == .recording || recordingSession.state == .paused
            || recordingSession.state == .arming || recordingSession.state == .draft
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isRecordingSelectedMeeting && !isRecordingActiveSession {
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
        .onChange(of: isRecordingActiveSession) { _, isRecording in
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
        .task { await loadScheduledRecordings() }
        .task { await loadVirtualOccurrences() }
        .task { await loadReminderActions() }
        .onChange(of: environment.contentRevision) { _, _ in
            Task { await loadDashboardModel() }
            Task { await loadScheduledRecordings() }
            Task { await loadVirtualOccurrences() }
            Task { await loadReminderActions() }
        }
        .audioImportSheets(
            isShowingPicker: $isShowingAudioImportPicker, environment: environment,
            onDone: { Task { await loadDashboardModel() } }
        )
        .sheet(item: $agendaSheet) { sheet in
            let onDone: () -> Void = {
                Task { await loadDashboardModel() }
                Task { await loadScheduledRecordings() }
            }
            switch sheet {
            case .create:
                AddAgendaItemFormView(environment: environment, onDone: onDone)
            case .editScheduledRecording(let item):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingScheduledRecording: item)
            case .editMeeting(let meeting):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingMeeting: meeting)
            case .editReminderAction(let action):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingReminderAction: action)
            }
        }
    }

    private func loadDashboardModel() async {
        dashboardModel = try? await environment.composeDashboard()
    }

    /// Today's schedules, excluding whatever a real `Meeting` row already
    /// represents (`.started`/`.completed` — see `.scheduled` case's doc
    /// comment on `PadAgendaRowView`) and whatever the user explicitly
    /// dismissed (`.cancelled`/`.skipped`). `.missed` stays included so a
    /// past-due reminder grays out in place rather than disappearing.
    private static let visibleScheduledStatuses: Set<ScheduledRecordingStatus> = [.pending, .notified, .missed]

    private func loadScheduledRecordings() async {
        guard environment.featureFlagProvider.isEnabled(.scheduledRecording),
            let workspaceID = environment.defaultPolicy?.workspaceID
        else {
            scheduledRecordings = []
            return
        }
        let all = (try? await environment.scheduledRecordingRepository.fetchAll(workspaceID: workspaceID)) ?? []
        scheduledRecordings = all.filter {
            Self.visibleScheduledStatuses.contains($0.status) && Calendar.current.isDateInToday($0.scheduledStart)
        }
    }

    private func startScheduledRecording(_ item: ScheduledRecording) async {
        await environment.scheduledRecordingCoordinator.handleStartAction(scheduledRecordingID: item.scheduledRecordingID)
        await loadDashboardModel()
        await loadScheduledRecordings()
    }

    private func modifyScheduledRecording(_ item: ScheduledRecording, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        if scope == .thisAndFollowing, let ruleID = item.recurrenceRuleID {
            await truncateRule(ruleID, before: item.scheduledStart)
        }
        agendaSheet = .editScheduledRecording(item)
    }

    private func cancelScheduledRecording(_ item: ScheduledRecording, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        if let ruleID = item.recurrenceRuleID {
            await applyCancelScope(scope, ruleID: ruleID, occurrenceDate: item.scheduledStart)
        }
        try? await environment.scheduledRecordingCoordinator.cancelSchedule(item)
        await loadScheduledRecordings()
        await loadVirtualOccurrences()
    }

    /// "Start Recording Now" for a `.notesOnly` agenda item (NSP-150) —
    /// `RecordingSession.start(existingMeetingID:)` promotes it in place;
    /// `.onChange(of: recordingSession.meetingID)` (this view's own body)
    /// then jumps the detail column to the recording canvas automatically.
    private func startExistingMeeting(_ meetingID: MeetingID) async {
        await recordingSession.start(existingMeetingID: meetingID)
    }

    private func modifyMeeting(_ meetingID: MeetingID, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        guard let meeting = try? await environment.meetingRepository.find(meetingID) else { return }
        if scope == .thisAndFollowing, let ruleID = meeting.recurrenceRuleID {
            await truncateRule(ruleID, before: meeting.startedAt)
        }
        agendaSheet = .editMeeting(meeting)
    }

    private func cancelMeeting(_ meetingID: MeetingID, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        if let meeting = try? await environment.meetingRepository.find(meetingID), let ruleID = meeting.recurrenceRuleID {
            await applyCancelScope(scope, ruleID: ruleID, occurrenceDate: meeting.startedAt)
        }
        try? await environment.deleteMeeting(meetingID)
        await loadDashboardModel()
        await loadVirtualOccurrences()
    }

    /// `.thisOccurrence`/`nil` writes a `.cancelled` exception for just this
    /// date; `.thisAndFollowing` also truncates the rule; `.allOccurrences`
    /// deletes the rule outright (its `ON DELETE SET NULL` FK detaches any
    /// other already-promoted row in the series rather than deleting those
    /// rows too — a disclosed simplification, NSP-159).
    private func applyCancelScope(
        _ scope: PadAgendaRowView.RecurrenceEditScope?, ruleID: RecurrenceRuleID, occurrenceDate: Date
    ) async {
        switch scope {
        case .thisOccurrence, .none:
            await writeCancelledException(ruleID: ruleID, date: occurrenceDate)
        case .thisAndFollowing:
            await truncateRule(ruleID, before: occurrenceDate)
            await writeCancelledException(ruleID: ruleID, date: occurrenceDate)
        case .allOccurrences:
            try? await environment.recurrenceRuleRepository.delete(ruleID)
        }
    }

    private func truncateRule(_ ruleID: RecurrenceRuleID, before date: Date) async {
        guard let rule = try? await environment.recurrenceRuleRepository.find(ruleID) else { return }
        var updated = rule
        updated.end = .onDate(date.addingTimeInterval(-1))
        try? await environment.recurrenceRuleRepository.update(updated, at: environment.clock.now())
    }

    private func writeCancelledException(ruleID: RecurrenceRuleID, date: Date) async {
        let now = environment.clock.now()
        let exception = RecurrenceException(
            recurrenceExceptionID: .generate(clock: environment.clock), recurrenceRuleID: ruleID,
            originalOccurrenceDate: date, kind: .cancelled, createdAt: now, updatedAt: now)
        try? await environment.recurrenceExceptionRepository.insert(exception, at: now)
    }

    private func loadVirtualOccurrences() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID,
            let dayInterval = Calendar.current.dateInterval(of: .day, for: environment.clock.now())
        else {
            virtualOccurrences = []
            return
        }
        let allMeetings =
            (try? await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)) ?? []
        let allScheduled = (try? await environment.scheduledRecordingRepository.fetchAll(workspaceID: workspaceID)) ?? []
        virtualOccurrences = await RecurringOccurrenceExpansion.expand(
            meetings: allMeetings, scheduledRecordings: allScheduled, window: dayInterval.start...dayInterval.end,
            environment: environment)
    }

    private func startVirtualOccurrence(_ occurrence: VirtualOccurrence) async {
        guard let policy = environment.defaultPolicy else { return }
        let now = environment.clock.now()
        if occurrence.isRecordedMeeting {
            let item = ScheduledRecording(
                scheduledRecordingID: .generate(clock: environment.clock), workspaceID: policy.workspaceID,
                title: occurrence.title, scheduledStart: occurrence.occurrenceDate,
                scheduledStop: occurrence.occurrenceDate.addingTimeInterval(1800), alertStyle: occurrence.alertStyle,
                notifyLeadTime: occurrence.notifyLeadTime, colorSlot: occurrence.colorSlot,
                recurrenceRuleID: occurrence.recurrenceRuleID, createdAt: now, updatedAt: now)
            try? await environment.scheduledRecordingCoordinator.create(item)
        } else {
            let meeting = Meeting(
                meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID, title: occurrence.title,
                captureMode: .import, originDeviceID: environment.deviceID, startedAt: occurrence.occurrenceDate,
                lifecycleState: .ready, policyID: policy.policyID, processingMode: policy.defaultProcessingMode,
                availability: .complete, colorSlot: occurrence.colorSlot, kind: occurrence.meetingKind,
                recurrenceRuleID: occurrence.recurrenceRuleID, createdAt: now, updatedAt: now)
            try? await environment.meetingRepository.insert(meeting, at: now)
        }
        await loadDashboardModel()
        await loadScheduledRecordings()
        await loadVirtualOccurrences()
    }

    private func skipVirtualOccurrence(_ occurrence: VirtualOccurrence) async {
        await writeCancelledException(ruleID: occurrence.recurrenceRuleID, date: occurrence.occurrenceDate)
        await loadVirtualOccurrences()
    }

    private func loadReminderActions() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else {
            reminderActions = []
            return
        }
        let all = (try? await environment.actionRepository.fetchAll(workspaceID: workspaceID)) ?? []
        reminderActions = all.filter { action in
            guard action.meetingID == nil else { return false }
            switch action.date {
            case .explicit(let date), .inferred(let date): return Calendar.current.isDateInToday(date)
            case .unresolved: return false
            }
        }
    }

    private func modifyReminderAction(_ action: Action) {
        agendaSheet = .editReminderAction(action)
    }

    private func cancelReminderAction(_ action: Action) async {
        try? await environment.actionRepository.delete(action.actionID)
        await loadReminderActions()
    }

    @ViewBuilder
    private var leadingColumn: some View {
        if (selectedArea ?? .myWork) == .dashboard {
            PadDashboardSidebar(
                model: dashboardModel, selectedArea: selectedArea ?? .myWork, width: isCompactPadWidth ? 280 : 304,
                scheduledRecordings: scheduledRecordings, virtualOccurrences: virtualOccurrences,
                reminderActions: reminderActions,
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
                onAddAgendaItem: { agendaSheet = .create },
                onStartScheduledRecording: { item in Task { await startScheduledRecording(item) } },
                onModifyScheduledRecording: { item, scope in Task { await modifyScheduledRecording(item, scope: scope) } },
                onCancelScheduledRecording: { item, scope in Task { await cancelScheduledRecording(item, scope: scope) } },
                onStartExistingMeeting: { id in Task { await startExistingMeeting(id) } },
                onModifyMeeting: { id, scope in Task { await modifyMeeting(id, scope: scope) } },
                onCancelMeeting: { id, scope in Task { await cancelMeeting(id, scope: scope) } },
                onStartVirtualOccurrence: { occurrence in Task { await startVirtualOccurrence(occurrence) } },
                onSkipVirtualOccurrence: { occurrence in Task { await skipVirtualOccurrence(occurrence) } },
                onModifyReminderAction: { modifyReminderAction($0) },
                onCancelReminderAction: { action in Task { await cancelReminderAction(action) } })
        } else {
            content.navigationTitle("North-Star Promise")
        }
    }

    /// Only these six — Actions/Threads/People/Calendar moved to
    /// `PadDashboardSidebar`'s own restricted nav list instead (this
    /// header briefly carried all 8 `AppTab.visibleCases`; reverted after
    /// that read as too much in one bar).
    private static let headerAreas: [AppTab] = [.myWork, .dashboard, .today, .library, .ask, .projects, .settings]

    /// The persistent, full-width top header — hidden only while
    /// `isRecordingSelectedMeeting` (recording or pre-recording
    /// note-taking), since the ruled-paper canvas takes the full window at
    /// that point and area-switching mid-session isn't a real use case.
    private var topHeaderBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: NSPSpacing.small) {
                ForEach(Self.headerAreas, id: \.self) { area in
                    let isSelected = (selectedArea ?? .myWork) == area
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
        switch selectedArea ?? .myWork {
        case .myWork:
            MyWorkView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
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
            CalendarView(
                environment: environment, onSelectMeeting: { selectedMeetingID = $0 },
                onStartMeeting: { id in Task { await startExistingMeeting(id) } })
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
        } else if isRecordingActiveSession {
            ScrollView {
                Group {
                    if recordingSession.state == .draft {
                        DraftingNotesCard(session: recordingSession, onSelectMeeting: nil)
                    } else {
                        ActiveSessionCard(session: recordingSession)
                    }
                }
                .padding(NSPSpacing.large)
            }
        } else if (selectedArea ?? .myWork) == .dashboard {
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
