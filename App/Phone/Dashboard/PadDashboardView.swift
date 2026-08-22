import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The iPad Dashboard's sidebar (`DASHBOARD_SPEC.md` §4.1) — brand, Recall
/// field, a restricted vertical nav list (Actions/Threads/People/Calendar
/// — the areas not already reachable from `PadRootView`'s top header),
/// Today's Agenda, and the pinned capture control. Only shown while
/// Dashboard is the selected top-header area; every other area's content
/// takes the whole leading column instead (`PadRootView.leadingColumn`).
struct PadDashboardSidebar: View {
    let model: DashboardModel?
    let selectedArea: AppTab
    /// 304pt at/above 1000pt window width, 280pt below it (§4.7).
    let width: CGFloat
    /// Today's pending Scheduled Recordings (docs/07 §2.1) — merged into
    /// `agendaSection` alongside `model.agenda` so a "Record automatically"
    /// agenda item (`AddAgendaItemFormView`) is visible the moment it's
    /// created, not only once its notification fires and promotes it to a
    /// real `Meeting`. `DashboardModel.agenda` itself stays real-`Meeting`s
    /// only (its own doc comment) — this list is layered on top here,
    /// iPad-sidebar-local, rather than widening the shared model.
    let scheduledRecordings: [ScheduledRecording]
    /// Future dates of a recurring series with no real row yet — `RecurringOccurrenceExpansion`'s
    /// output, merged in alongside `scheduledRecordings` for the same
    /// "visible the moment the pattern implies it, not only once promoted"
    /// reason (NSP-160).
    let virtualOccurrences: [VirtualOccurrence]
    /// Today's due-dated, no-meeting `Action`s — "Action Reminder"'s
    /// collapsed home ("The Spine" recommendation, 2026-08-22). Merged in
    /// the same way as `scheduledRecordings`/`virtualOccurrences` since
    /// `DashboardModel.agenda` stays real-`Meeting`s only.
    let reminderActions: [Action]
    let onSelectArea: (AppTab) -> Void
    let onSelectMeeting: (MeetingID) -> Void
    let onRecall: () -> Void
    let onStartMeeting: () -> Void
    let onStartNotesOnly: () -> Void
    let onStartMentalNote: () -> Void
    let onImportAudio: () -> Void
    /// `nil` when `FeatureFlag.ambientMode` is off.
    let onStartAmbientMode: (() -> Void)?
    let onAddAgendaItem: () -> Void
    let onStartScheduledRecording: (ScheduledRecording) -> Void
    let onModifyScheduledRecording: (ScheduledRecording, PadAgendaRowView.RecurrenceEditScope?) -> Void
    let onCancelScheduledRecording: (ScheduledRecording, PadAgendaRowView.RecurrenceEditScope?) -> Void
    /// "Start Recording Now" for a not-yet-recorded (`.notesOnly`) agenda
    /// item (NSP-150) — distinct from `onStartMeeting` above, which starts
    /// a brand-new ad-hoc meeting from the capture control.
    let onStartExistingMeeting: (MeetingID) -> Void
    let onModifyMeeting: (MeetingID, PadAgendaRowView.RecurrenceEditScope?) -> Void
    let onCancelMeeting: (MeetingID, PadAgendaRowView.RecurrenceEditScope?) -> Void
    let onStartVirtualOccurrence: (VirtualOccurrence) -> Void
    let onSkipVirtualOccurrence: (VirtualOccurrence) -> Void
    let onModifyReminderAction: (Action) -> Void
    let onCancelReminderAction: (Action) -> Void

    /// Everything the top header doesn't already carry
    /// (`PadRootView.headerAreas`).
    private static let sidebarAreas: [AppTab] = [.actions, .threads, .people, .calendar]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                brand
                DashboardRecallField(corpusCount: model?.corpusCount ?? 0, action: onRecall)
                    .padding(.top, 18)
                navList.padding(.top, 20)
            }
            .padding(.horizontal, Metrics.screenMarginPadSidebar)
            .padding(.top, 24)

            Divider().overlay(Palette.divider).padding(.top, 22).padding(.horizontal, 6)

            agendaSection
                .padding(.horizontal, Metrics.screenMarginPadSidebar)
                .padding(.top, 18)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                DashboardNotesOnlyButton(action: onStartNotesOnly)
                DashboardCaptureButton(
                    isRecording: false, onStartMeeting: onStartMeeting, onStartMentalNote: onStartMentalNote,
                    onImportAudio: onImportAudio, onStartAmbientMode: onStartAmbientMode
                )
                DashboardBrainDumpButton(action: onStartMentalNote)
            }
            .padding(.bottom, 28)
        }
        .frame(width: width)
        .background(Palette.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 1) }
    }

    private var brand: some View {
        Text("North-Star Promise")
            .font(Typo.ui(20, .semibold))
            .foregroundStyle(Palette.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var navList: some View {
        VStack(spacing: 2) {
            ForEach(Self.sidebarAreas, id: \.self) { area in
                NavRow(area: area, count: navCount(for: area), isSelected: area == selectedArea) {
                    onSelectArea(area)
                }
            }
        }
    }

    private func navCount(for area: AppTab) -> Int? {
        guard let model else { return nil }
        switch area {
        case .threads: return model.navCounts.openThreads
        case .actions: return model.navCounts.openActionsIOwe
        default: return nil
        }
    }

    @ViewBuilder
    private var agendaSection: some View {
        HStack {
            Text("TODAY'S AGENDA")
                .font(Typo.ui(18, .extrabold, relativeTo: .caption2))
                .tracking(0.14 * 18)
                .foregroundStyle(Palette.textQuaternary)
            Spacer()
            Button(action: onAddAgendaItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.accent.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to today's agenda")
        }
        if !agendaRows.isEmpty {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(agendaRows) { rowView(for: $0) }
                }
                .padding(.top, 10)
            }
        } else {
            Text("Nothing scheduled. Tap Start capture for an ad-hoc meeting.")
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textQuaternary)
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func rowView(for row: AgendaRow) -> some View {
        switch row {
        case .meeting(let item): meetingRow(item)
        case .scheduled(let recording): scheduledRow(recording)
        case .virtual(let occurrence): virtualRow(occurrence)
        case .reminder(let action): reminderRow(action)
        }
    }

    private func meetingRow(_ item: AgendaItem) -> some View {
        PadAgendaRowView(
            time: item.start, title: item.title, subtitle: item.continuityFact,
            railColor: railColor(threadColorSlot: item.thread?.colorSlot, ownColorSlot: item.colorSlot),
            isPast: item.state == .past, isHighlighted: item.state == .next || item.state == .live,
            showsBell: false, isRecurring: item.recurrenceRuleID != nil,
            menu: item.kind == .recorded
                ? nil
                : PadAgendaRowView.MenuActions(
                    onStart: { onStartExistingMeeting(item.meetingID) },
                    onModify: { onModifyMeeting(item.meetingID, $0) },
                    onCancel: { onCancelMeeting(item.meetingID, $0) }),
            onTap: { onSelectMeeting(item.meetingID) })
    }

    private func scheduledRow(_ recording: ScheduledRecording) -> some View {
        PadAgendaRowView(
            time: recording.scheduledStart, title: recording.title,
            subtitle: recording.status == .missed ? "Recorded Meeting · Missed" : "Recorded Meeting",
            railColor: railColor(threadColorSlot: nil, ownColorSlot: recording.colorSlot),
            isPast: recording.status == .missed, isHighlighted: false,
            showsBell: recording.status == .pending || recording.status == .notified,
            isRecurring: recording.recurrenceRuleID != nil,
            menu: PadAgendaRowView.MenuActions(
                onStart: { onStartScheduledRecording(recording) },
                onModify: { onModifyScheduledRecording(recording, $0) },
                onCancel: { onCancelScheduledRecording(recording, $0) }),
            onTap: nil)
    }

    private func virtualRow(_ occurrence: VirtualOccurrence) -> some View {
        PadAgendaRowView(
            time: occurrence.occurrenceDate, title: occurrence.title, subtitle: occurrence.subtitle,
            railColor: railColor(threadColorSlot: nil, ownColorSlot: occurrence.colorSlot),
            isPast: false, isHighlighted: false, showsBell: false, isRecurring: true,
            menu: PadAgendaRowView.MenuActions(
                onStart: { onStartVirtualOccurrence(occurrence) },
                onModify: { _ in }, onCancel: { _ in onSkipVirtualOccurrence(occurrence) }),
            onTap: nil)
    }

    private func reminderRow(_ action: Action) -> some View {
        let isPast = Self.resolvedDate(action) < Date()
        return PadAgendaRowView(
            time: Self.resolvedDate(action), title: action.text, subtitle: "Action Reminder",
            railColor: railColor(threadColorSlot: nil, ownColorSlot: 0), isPast: isPast, isHighlighted: false,
            showsBell: false, isRecurring: false,
            menu: PadAgendaRowView.MenuActions(
                onStart: nil, onModify: { _ in onModifyReminderAction(action) },
                onCancel: { _ in onCancelReminderAction(action) }),
            onTap: nil)
    }

    private static func resolvedDate(_ action: Action) -> Date {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date
        case .unresolved: return .distantFuture
        }
    }

    /// `model.agenda` (real `Meeting`s), `scheduledRecordings` (pending,
    /// not yet recorded), `virtualOccurrences` (a recurring series' future
    /// dates with no real row yet, NSP-160), and `reminderActions`
    /// (collapsed "Action Reminder"s, "The Spine", 2026-08-22) merged into
    /// one chronological list.
    private enum AgendaRow: Identifiable {
        case meeting(AgendaItem)
        case scheduled(ScheduledRecording)
        case virtual(VirtualOccurrence)
        case reminder(Action)

        var id: String {
            switch self {
            case .meeting(let item): return "m-\(item.meetingID)"
            case .scheduled(let recording): return "s-\(recording.scheduledRecordingID)"
            case .virtual(let occurrence): return "v-\(occurrence.id)"
            case .reminder(let action): return "r-\(action.actionID)"
            }
        }

        var start: Date {
            switch self {
            case .meeting(let item): return item.start
            case .scheduled(let recording): return recording.scheduledStart
            case .virtual(let occurrence): return occurrence.occurrenceDate
            case .reminder(let action):
                switch action.date {
                case .explicit(let date), .inferred(let date): return date
                case .unresolved: return .distantFuture
                }
            }
        }
    }

    private var agendaRows: [AgendaRow] {
        let meetingRows = (model?.agenda ?? []).map(AgendaRow.meeting)
        let scheduledRows = scheduledRecordings.map(AgendaRow.scheduled)
        let virtualRows = virtualOccurrences.map(AgendaRow.virtual)
        let reminderRows = reminderActions.map(AgendaRow.reminder)
        return (meetingRows + scheduledRows + virtualRows + reminderRows).sorted { $0.start < $1.start }
    }

    private func railColor(threadColorSlot: Int?, ownColorSlot: Int) -> Color {
        PadAgendaRowView.railColor(threadColorSlot: threadColorSlot, ownColorSlot: ownColorSlot)
    }
}

private struct NavRow: View {
    let area: AppTab
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: area.symbolName).font(.system(size: 15))
                Text(area.title).font(Typo.ui(15.5, isSelected ? .extrabold : .medium))
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").font(Typo.ui(15.5, isSelected ? .extrabold : .bold))
                }
            }
            .foregroundStyle(isSelected ? Palette.accent.foreground : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                isSelected ? Palette.accent.background : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The sidebar's unified agenda row (§4.2) — a thread rail rather than the
/// phone timeline's dot, per the spec's own distinct iPad row anatomy. Used
/// for both real `Meeting`s and pending `ScheduledRecording` placeholders,
/// so "Add to Today's Agenda"'s three Meeting Types all render identically:
/// time left of the colored rail, title/type-subtitle to its right, a bell
/// while a reminder is still pending, and a "…" menu for anything the user
/// created directly (never for an organically-captured, already-threaded
/// meeting, where `menu` is `nil`).
struct PadAgendaRowView: View {
    let time: Date
    let title: String
    let subtitle: String
    let railColor: Color
    /// Past items stay in the list, just grayed — never removed.
    let isPast: Bool
    let isHighlighted: Bool
    let showsBell: Bool
    /// Non-nil for any row that belongs to a recurring series (NSP-160) —
    /// draws the ⟳ badge and, when `menu.onModify`/`onCancel` is present,
    /// routes those two through the three-way scope prompt below instead
    /// of calling straight through.
    var isRecurring: Bool = false
    let menu: MenuActions?
    let onTap: (() -> Void)?

    /// Outlook's classic "This event is part of a series" three options.
    /// `nil` on `onModify`/`onCancel`'s scope means "not recurring, act
    /// immediately" — every existing non-recurring call site keeps working
    /// unchanged by just ignoring the parameter.
    enum RecurrenceEditScope {
        case thisOccurrence
        case thisAndFollowing
        case allOccurrences
    }

    struct MenuActions {
        let onStart: (() -> Void)?
        let onModify: (RecurrenceEditScope?) -> Void
        let onCancel: (RecurrenceEditScope?) -> Void
    }

    private enum PendingScopeAction: Identifiable {
        case modify, cancel
        var id: Self { self }
    }

    @State private var pendingScopeAction: PendingScopeAction?

    /// A Thread's own color wins when one is assigned (unchanged rail
    /// behavior for organically-threaded meetings); otherwise the item's
    /// own `colorSlot` (`AddAgendaItemFormView`'s color picker) — modulo
    /// guards against a future `Palette.threadSlots` resize.
    static func railColor(threadColorSlot: Int?, ownColorSlot: Int) -> Color {
        if let threadColorSlot { return Palette.threadSlots[threadColorSlot] }
        let count = Palette.threadSlots.count
        return Palette.threadSlots[((ownColorSlot % count) + count) % count]
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(time.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Typo.ui(14.5, .bold))
                .foregroundStyle(isPast ? Palette.textMuted : Palette.textPrimary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            ThreadRail(color: railColor, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(Typo.ui(15, isPast ? .medium : .bold))
                        .foregroundStyle(isPast ? Palette.textQuaternary : Palette.textPrimary)
                        .lineLimit(1)
                    if isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isPast ? Palette.textQuaternary : railColor)
                            .accessibilityLabel("Recurring")
                    }
                }
                Text(subtitle).font(Typo.ui(12.5, .semibold)).foregroundStyle(railColor).lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsBell {
                Image(systemName: "bell.fill").font(.system(size: 13)).foregroundStyle(railColor)
            }
            if let menu {
                Menu {
                    if let onStart = menu.onStart {
                        Button("Start Event", systemImage: "record.circle", action: onStart)
                    }
                    Button("Modify Event", systemImage: "pencil") {
                        if isRecurring { pendingScopeAction = .modify } else { menu.onModify(nil) }
                    }
                    Button("Cancel Event", systemImage: "xmark.circle", role: .destructive) {
                        if isRecurring { pendingScopeAction = .cancel } else { menu.onCancel(nil) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(isHighlighted ? Palette.fill : Color.clear, in: .rect(cornerRadius: 9, style: .continuous))
        .onTapGesture { onTap?() }
        .confirmationDialog(
            "This event is part of a series", isPresented: scopeDialogIsPresented, titleVisibility: .visible
        ) {
            Button("This occurrence") { resolveScope(.thisOccurrence) }
            Button("This and following occurrences") { resolveScope(.thisAndFollowing) }
            Button("All occurrences") { resolveScope(.allOccurrences) }
            Button("Cancel", role: .cancel) { pendingScopeAction = nil }
        }
    }

    private var scopeDialogIsPresented: Binding<Bool> {
        Binding(get: { pendingScopeAction != nil }, set: { if !$0 { pendingScopeAction = nil } })
    }

    private func resolveScope(_ scope: RecurrenceEditScope) {
        guard let menu, let pendingScopeAction else { return }
        switch pendingScopeAction {
        case .modify: menu.onModify(scope)
        case .cancel: menu.onCancel(scope)
        }
        self.pendingScopeAction = nil
    }
}

/// The iPad Dashboard's main column (§4.3–§4.6) — occupies `PadRootView`'s
/// detail column whenever nothing is selected and the Dashboard area is
/// active (selecting a meeting swaps that same column to the real
/// `MeetingDetailView`/canvas, this app's existing two-column pattern).
struct PadDashboardMainColumn: View {
    let model: DashboardModel?
    /// Below 1000pt window width (§4.7): "Threads in motion" drops to 2
    /// columns showing the top 2, and "Captured this morning" stacks to 1
    /// column.
    let isCompactWidth: Bool
    let onSelectMeeting: (MeetingID) -> Void
    let onSelectArea: (AppTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let brief = model?.nextUp {
                    NextUpCard(
                        brief: brief, onOpenBrief: { onSelectMeeting(brief.meeting.meetingID) },
                        onJoin: { onSelectMeeting(brief.meeting.meetingID) })
                } else if model != nil {
                    ContentUnavailableView(
                        "That's the day", systemImage: "checkmark.circle",
                        description: Text("Nothing else scheduled today."))
                }
                threadsInMotion
                HStack(alignment: .top, spacing: 20) {
                    needsYou
                    signals
                }
                capturedToday
            }
            .padding(.top, 38)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(Typo.ui(10.5, .extrabold, relativeTo: .caption2))
                .tracking(0.16 * 10.5)
                .foregroundStyle(Palette.textQuaternary)
            Text("Today").font(Typo.display(42))
        }
    }

    private var threadColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: isCompactWidth ? 2 : 3)
    }

    @ViewBuilder
    private var threadsInMotion: some View {
        if let cards = model?.threadsInMotion, !cards.isEmpty {
            let shown = isCompactWidth ? Array(cards.prefix(2)) : cards
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Threads in motion", trailingAction: ("All \(cards.count)", { onSelectArea(.threads) }))
                LazyVGrid(columns: threadColumns, spacing: 14) {
                    ForEach(shown) { card in
                        Button {
                            onSelectArea(.threads)
                        } label: {
                            ThreadMotionCard(card: card, action: {})
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var needsYou: some View {
        if let needsYou = model?.needsYou, !needsYou.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "Needs you",
                    inlineChip: needsYou.overdueCount > 0 ? ("\(needsYou.overdueCount) overdue", .danger) : nil,
                    trailingAction: ("\(needsYou.openCount) open", { onSelectArea(.actions) }))
                VStack(spacing: 0) {
                    ForEach(needsYou.items) { item in NeedsYouRow(item: item, onComplete: {}) }
                }
                .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var signals: some View {
        if let signals = model?.signals, !signals.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeader("What your history noticed")
                ForEach(signals) { DashboardSignalCard(signal: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capturedColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: isCompactWidth ? 1 : 2)
    }

    @ViewBuilder
    private var capturedToday: some View {
        if let cards = model?.capturedToday, !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Captured this morning")
                LazyVGrid(columns: capturedColumns, spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            onSelectMeeting(card.meetingID)
                        } label: {
                            RecapCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RecapCardView: View {
    let card: RecapCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let thread = card.thread {
                    ThreadDot(color: Palette.threadSlots[thread.colorSlot])
                }
                Text(card.title).font(Typo.ui(13.5, .extrabold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(card.durationMinutes) min").font(Typo.ui(11, .semibold)).foregroundStyle(Palette.textQuaternary)
            }
            if !card.headline.isEmpty {
                Text(card.headline).font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
    }
}
