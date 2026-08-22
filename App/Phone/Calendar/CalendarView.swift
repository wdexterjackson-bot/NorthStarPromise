import NSPCore
import NSPDesignSystem
import SwiftUI

/// A month-grid view of this workspace's meetings — genuinely new (iPad's
/// left-panel restructuring introduced this as its own top-header area,
/// not a rename of `ProjectsListView`), built over data this app already
/// has (`Meeting.startedAt`) rather than a new EventKit integration; the
/// device's own calendar events are a separate, larger, deferred feature
/// (`docs/09-BACKLOG.md`'s "Calendar-driven agenda" — reading *external*
/// events, not showing this app's own recordings). Tapping a day shows
/// that day's meetings below the grid; tapping a meeting opens it, same
/// `onSelectMeeting`/`NavigationLink` dual pattern every other list screen
/// in this app uses.
@MainActor
struct CalendarView: View {
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?
    /// "Start Recording Now" for a `.notesOnly` agenda item (NSP-150) —
    /// `nil` on iPhone (no `RecordingSession` reaches this screen there
    /// today; Calendar is iPad-only per `AppTab`'s own doc comment).
    var onStartMeeting: ((MeetingID) -> Void)?

    @State private var displayedMonth = Date()
    @State private var selectedDay: Date?
    @State private var meetings: [Meeting] = []
    /// Today's-and-later pending Scheduled Recordings (docs/07 §2.1) —
    /// merged into the day-dot indicator and `selectedDaySection` so an
    /// agenda item created via `AddAgendaItemFormView`'s "Record
    /// automatically" path is visible here too, not only once its
    /// notification fires and promotes it to a real `Meeting`.
    @State private var scheduledRecordings: [ScheduledRecording] = []
    /// The displayed month's recurring series' future dates with no real
    /// row yet — `RecurringOccurrenceExpansion`'s output (NSP-160).
    @State private var virtualOccurrences: [VirtualOccurrence] = []
    /// The workspace's due-dated, no-meeting `Action`s — "Action Reminder"'s
    /// collapsed home ("The Spine" recommendation, 2026-08-22).
    @State private var reminderActions: [Action] = []
    @State private var loadError: String?
    @State private var agendaSheet: AgendaSheet?

    private let calendar = Calendar.current

    /// Same shape as `PadRootView.AgendaSheet` — mirrored locally rather
    /// than shared since each view owns its own sheet-presentation state.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NSPSpacing.large) {
                if let loadError {
                    Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
                monthNavigator
                weekdayHeader
                dayGrid
                Divider().overlay(Palette.divider)
                selectedDaySection
            }
            .padding(NSPSpacing.large)
        }
        .background(Palette.canvas)
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    agendaSheet = .create
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add to calendar")
            }
        }
        .task { await load() }
        .onChange(of: environment.contentRevision) { _, _ in Task { await load() } }
        .onChange(of: displayedMonth) { _, _ in Task { await loadVirtualOccurrences() } }
        .sheet(item: $agendaSheet) { sheet in
            let onDone: () -> Void = { Task { await load() } }
            switch sheet {
            case .create:
                AddAgendaItemFormView(
                    environment: environment, onDone: onDone, initialDate: selectedDay ?? Date())
            case .editScheduledRecording(let item):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingScheduledRecording: item)
            case .editMeeting(let meeting):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingMeeting: meeting)
            case .editReminderAction(let action):
                AddAgendaItemFormView(environment: environment, onDone: onDone, existingReminderAction: action)
            }
        }
    }

    // MARK: - Header

    private var monthNavigator: some View {
        HStack {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(Typo.display(28))
            Spacer()
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain).accessibilityLabel("Previous month")
            Button("Today") {
                displayedMonth = Date()
                selectedDay = calendar.startOfDay(for: Date())
            }
            .font(Typo.ui(12, .semibold))
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain).accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                Text(symbol)
                    .font(Typo.ui(10.5, .bold))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let startOfDay = calendar.startOfDay(for: day)
        let count =
            (meetingsByDay[startOfDay]?.count ?? 0) + (scheduledByDay[startOfDay]?.count ?? 0)
            + (virtualByDay[startOfDay]?.count ?? 0) + (reminderByDay[startOfDay]?.count ?? 0)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Typo.ui(13, isToday ? .extrabold : .semibold))
                    .foregroundStyle(isSelected ? .white : (isToday ? Palette.accent.foreground : Palette.textPrimary))
                Circle()
                    .fill(count > 0 ? (isSelected ? .white : Palette.accent.foreground) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected ? Palette.accent.foreground : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.month(.wide).day().year()))
        .accessibilityValue(count > 0 ? "\(count) meeting\(count == 1 ? "" : "s")" : "No meetings")
    }

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDaySection: some View {
        let day = selectedDay ?? calendar.startOfDay(for: Date())
        let startOfDay = calendar.startOfDay(for: day)
        let dayMeetings = meetingsByDay[startOfDay] ?? []
        let dayScheduled = scheduledByDay[startOfDay] ?? []
        let dayVirtual = virtualByDay[startOfDay] ?? []
        let dayReminders = reminderByDay[startOfDay] ?? []
        Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(Typo.ui(15, .bold))
        if dayMeetings.isEmpty && dayScheduled.isEmpty && dayVirtual.isEmpty && dayReminders.isEmpty {
            Text("No meetings this day.").font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textQuaternary)
        } else {
            VStack(spacing: 1) {
                ForEach(dayMeetings.sorted { $0.startedAt < $1.startedAt }) { meetingRow($0) }
                ForEach(dayScheduled.sorted { $0.scheduledStart < $1.scheduledStart }) { scheduledRow($0) }
                ForEach(dayVirtual.sorted { $0.occurrenceDate < $1.occurrenceDate }) { virtualRow($0) }
                ForEach(dayReminders.sorted { Self.resolvedDate($0) < Self.resolvedDate($1) }) { reminderRow($0) }
            }
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let isPast = (meeting.endedAt ?? meeting.startedAt) < Date()
        return PadAgendaRowView(
            time: meeting.startedAt, title: meeting.isTitleSensitive ? "Untitled meeting" : meeting.title,
            subtitle: subtitle(for: meeting),
            railColor: PadAgendaRowView.railColor(threadColorSlot: nil, ownColorSlot: meeting.colorSlot),
            isPast: isPast, isHighlighted: false, showsBell: false, isRecurring: meeting.recurrenceRuleID != nil,
            menu: meeting.kind == .recorded
                ? nil
                : PadAgendaRowView.MenuActions(
                    onStart: onStartMeeting.map { handler in { handler(meeting.meetingID) } },
                    onModify: { scope in Task { await modifyMeeting(meeting, scope: scope) } },
                    onCancel: { scope in Task { await cancelMeeting(meeting, scope: scope) } }),
            onTap: { onSelectMeeting?(meeting.meetingID) }
        )
        .nspCard()
    }

    private func scheduledRow(_ item: ScheduledRecording) -> some View {
        PadAgendaRowView(
            time: item.scheduledStart, title: item.title,
            subtitle: item.status == .missed ? "Recorded Meeting · Missed" : "Recorded Meeting",
            railColor: PadAgendaRowView.railColor(threadColorSlot: nil, ownColorSlot: item.colorSlot),
            isPast: item.status == .missed, isHighlighted: false,
            showsBell: item.status == .pending || item.status == .notified, isRecurring: item.recurrenceRuleID != nil,
            menu: PadAgendaRowView.MenuActions(
                onStart: { Task { await startScheduledRecording(item) } },
                onModify: { scope in Task { await modifyScheduledRecording(item, scope: scope) } },
                onCancel: { scope in Task { await cancelScheduledRecording(item, scope: scope) } }),
            onTap: nil
        )
        .nspCard()
    }

    private func virtualRow(_ occurrence: VirtualOccurrence) -> some View {
        PadAgendaRowView(
            time: occurrence.occurrenceDate, title: occurrence.title, subtitle: occurrence.subtitle,
            railColor: PadAgendaRowView.railColor(threadColorSlot: nil, ownColorSlot: occurrence.colorSlot),
            isPast: false, isHighlighted: false, showsBell: false, isRecurring: true,
            menu: PadAgendaRowView.MenuActions(
                onStart: { Task { await startVirtualOccurrence(occurrence) } },
                onModify: { _ in }, onCancel: { _ in Task { await skipVirtualOccurrence(occurrence) } }),
            onTap: nil
        )
        .nspCard()
    }

    private func reminderRow(_ action: Action) -> some View {
        let isPast = Self.resolvedDate(action) < Date()
        return PadAgendaRowView(
            time: Self.resolvedDate(action), title: action.text, subtitle: "Action Reminder",
            railColor: PadAgendaRowView.railColor(threadColorSlot: nil, ownColorSlot: 0), isPast: isPast,
            isHighlighted: false, showsBell: false, isRecurring: false,
            menu: PadAgendaRowView.MenuActions(
                onStart: nil, onModify: { _ in agendaSheet = .editReminderAction(action) },
                onCancel: { _ in Task { await cancelReminderAction(action) } }),
            onTap: nil
        )
        .nspCard()
    }

    private static func resolvedDate(_ action: Action) -> Date {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date
        case .unresolved: return .distantFuture
        }
    }

    private func subtitle(for meeting: Meeting) -> String {
        switch meeting.kind {
        case .notesOnly: return "Meeting with Notes"
        case .recorded: return "Recorded Meeting"
        }
    }

    // MARK: - Data

    private var meetingsByDay: [Date: [Meeting]] {
        Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.startedAt) }
    }

    private var scheduledByDay: [Date: [ScheduledRecording]] {
        Dictionary(grouping: scheduledRecordings) { calendar.startOfDay(for: $0.scheduledStart) }
    }

    private var virtualByDay: [Date: [VirtualOccurrence]] {
        Dictionary(grouping: virtualOccurrences) { calendar.startOfDay(for: $0.occurrenceDate) }
    }

    private var reminderByDay: [Date: [Action]] {
        Dictionary(grouping: reminderActions) { calendar.startOfDay(for: Self.resolvedDate($0)) }
    }

    /// `nil` entries are the leading blanks before the 1st falls on the
    /// grid's first column — `LazyVGrid` just renders them as empty cells.
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: monthInterval.start) }
        return Array(repeating: nil, count: leadingBlanks) + days
    }

    private func shiftMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }

    private static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// `.started`/`.completed` are excluded — the real `Meeting` row a
    /// start promotes them to already appears in `meetings`, so keeping
    /// both would duplicate the day's rows. `.cancelled`/`.skipped` are
    /// excluded as explicit user dismissals; `.missed` stays so a past-due
    /// reminder grays out in place rather than disappearing.
    private static let visibleScheduledStatuses: Set<ScheduledRecordingStatus> = [.pending, .notified, .missed]

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            meetings = try await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
            if environment.featureFlagProvider.isEnabled(.scheduledRecording) {
                let all = try await environment.scheduledRecordingRepository.fetchAll(workspaceID: workspaceID)
                scheduledRecordings = all.filter { Self.visibleScheduledStatuses.contains($0.status) }
            }
            reminderActions = try await environment.actionRepository.fetchAll(workspaceID: workspaceID).filter {
                $0.meetingID == nil && Self.resolvedDate($0) != .distantFuture
            }
            if selectedDay == nil { selectedDay = calendar.startOfDay(for: Date()) }
        } catch {
            loadError = "\(error)"
        }
        await loadVirtualOccurrences()
    }

    private func cancelReminderAction(_ action: Action) async {
        try? await environment.actionRepository.delete(action.actionID)
        await load()
    }

    private func loadVirtualOccurrences() async {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            virtualOccurrences = []
            return
        }
        virtualOccurrences = await RecurringOccurrenceExpansion.expand(
            meetings: meetings, scheduledRecordings: scheduledRecordings,
            window: monthInterval.start...monthInterval.end, environment: environment)
    }

    private func startScheduledRecording(_ item: ScheduledRecording) async {
        await environment.scheduledRecordingCoordinator.handleStartAction(scheduledRecordingID: item.scheduledRecordingID)
        await load()
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
        await load()
    }

    private func modifyMeeting(_ meeting: Meeting, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        if scope == .thisAndFollowing, let ruleID = meeting.recurrenceRuleID {
            await truncateRule(ruleID, before: meeting.startedAt)
        }
        agendaSheet = .editMeeting(meeting)
    }

    private func cancelMeeting(_ meeting: Meeting, scope: PadAgendaRowView.RecurrenceEditScope?) async {
        if let ruleID = meeting.recurrenceRuleID {
            await applyCancelScope(scope, ruleID: ruleID, occurrenceDate: meeting.startedAt)
        }
        try? await environment.deleteMeeting(meeting.meetingID)
        await load()
    }

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
        await load()
    }

    private func skipVirtualOccurrence(_ occurrence: VirtualOccurrence) async {
        await writeCancelledException(ruleID: occurrence.recurrenceRuleID, date: occurrence.occurrenceDate)
        await loadVirtualOccurrences()
    }
}
