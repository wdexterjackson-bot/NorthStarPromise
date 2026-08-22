import Foundation
import NSPCore
import NSPPersistence

/// The repositories `DashboardComposer.compose` reads from — grouped into
/// one type purely to keep `compose`'s own signature under this repo's
/// 5-parameter budget (same reasoning as `AppEnvironmentFactories`'s
/// `CoreRepositories`).
public struct DashboardRepositories: Sendable {
    public let meeting: any MeetingRepository
    public let action: any ActionRepository
    public let decision: any DecisionRepository
    public let thread: any NSPThreadRepository

    public init(
        meeting: any MeetingRepository, action: any ActionRepository, decision: any DecisionRepository,
        thread: any NSPThreadRepository
    ) {
        self.meeting = meeting
        self.action = action
        self.decision = decision
        self.thread = thread
    }
}

/// Assembles the real `DashboardModel` from live repositories
/// (`DASHBOARD_SPEC.md` §6/§7). Deliberately honest rather than clever: it
/// reads what already exists (meetings, thread linkage, open actions and
/// decisions) and applies only the spec's non-ML derivation rules (status
/// from overdue/defer/staleness checks, simple ranking, counting). Anything
/// the spec's real pipeline would need — diarization, the scored auto-join
/// formula, commitment extraction, the signals engine, recap generation —
/// is out of scope for this pass (Dashboard redesign plan's "Deferred"
/// section); those fields render `nil`/empty here, which the View layer's
/// spec'd empty states (§8.1) already handle correctly. `async` because
/// every repository call is — not because this does anything expensive;
/// there is no network, embedding, or LLM call anywhere in this file.
public enum DashboardComposer {
    private static let openActionStatuses: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]
    // Not `private` — `DashboardComposer+Threads.swift`'s `deriveThreadStatuses`
    // (a separate file, same target) reads this too; Swift's `private` is
    // file-scoped, not type-scoped.
    static let openDecisionStatuses: Set<DecisionStatus> = [.proposed]
    private static let recapReadyStates: Set<MeetingState> = [.readyForReview, .approved, .edited, .shared]

    /// Everything the per-agenda-row helpers need, bundled purely to keep
    /// their own signatures under the 5-parameter budget.
    private struct BuildContext {
        let allMeetings: [Meeting]
        let todaysMeetings: [Meeting]
        let threadsByID: [NSPThreadID: NSPThread]
        let threadIDsByMeeting: [MeetingID: [NSPThreadID]]
        let openActions: [Action]
        let meetingRepository: any MeetingRepository
    }

    /// The facts about one row that `continuityFact` picks a sub-line from.
    private struct AgendaRowFacts {
        let state: AgendaRowState
        let recapReady: Bool
        let threadRef: ThreadRef?
    }

    public static func compose(
        workspaceID: WorkspaceID, repositories: DashboardRepositories, clock: any Clock
    ) async throws -> DashboardModel {
        let now = clock.now()
        let calendar = Calendar.current
        let allMeetings = try await repositories.meeting.fetchAll(workspaceID: workspaceID, includeDeleted: false)
        let threads = try await repositories.thread.fetchAll(workspaceID: workspaceID)
        let threadsByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.threadID, $0) })
        let meetingIDsByThread = try await repositories.thread.fetchMeetingIDsByThread(workspaceID: workspaceID)
        let threadIDsByMeeting = Self.invertAndRank(meetingIDsByThread, threadsByID: threadsByID)
        let allActions = try await repositories.action.fetchAll(workspaceID: workspaceID)
        let openActions = allActions.filter { openActionStatuses.contains($0.status) }
        let allDecisions = try await repositories.decision.fetchAll(workspaceID: workspaceID)
        let derivedStatuses = deriveThreadStatuses(
            threads: threads,
            inputs: ThreadStatusInputs(
                allMeetings: allMeetings, meetingIDsByThread: meetingIDsByThread, openActions: openActions,
                allDecisions: allDecisions),
            now: now)

        let todaysMeetings =
            allMeetings.filter { calendar.isDateInToday($0.startedAt) }.sorted { $0.startedAt < $1.startedAt }
        let context = BuildContext(
            allMeetings: allMeetings, todaysMeetings: todaysMeetings, threadsByID: threadsByID,
            threadIDsByMeeting: threadIDsByMeeting, openActions: openActions, meetingRepository: repositories.meeting)

        var agenda: [AgendaItem] = []
        for meeting in todaysMeetings {
            agenda.append(try await makeAgendaItem(meeting, context, now: now))
        }

        let nextUp = try await makeNextUp(agenda: agenda, context: context, now: now)
        let threadCards = makeThreadCards(
            threads: threads, meetingIDsByThread: meetingIDsByThread, derivedStatuses: derivedStatuses)
        let needsYou = makeNeedsYou(
            openActions: openActions, allMeetings: allMeetings, threadsByID: threadsByID, now: now)
        let signals = makeSignals(threads: threads, derivedStatuses: derivedStatuses, now: now)
        let capturedToday = makeCapturedToday(
            todaysMeetings: todaysMeetings, threadIDsByMeeting: threadIDsByMeeting, threadsByID: threadsByID)

        let openThreadCount = threads.filter { (derivedStatuses[$0.threadID] ?? $0.status) != .closed }.count
        let headline =
            "\(agenda.count) meeting\(agenda.count == 1 ? "" : "s") · "
            + "\(openThreadCount) thread\(openThreadCount == 1 ? "" : "s") in motion"

        return DashboardModel(
            date: now, headline: headline, corpusCount: allMeetings.count, agenda: agenda, nextUp: nextUp,
            threadsInMotion: threadCards, needsYou: needsYou, signals: signals, capturedToday: capturedToday,
            navCounts: NavCounts(
                todayMeetings: agenda.count, openThreads: openThreadCount,
                openActionsIOwe: openActions.filter { $0.direction == .iOwe }.count, libraryTotal: allMeetings.count))
    }

    // MARK: - Agenda

    private static func makeAgendaItem(
        _ meeting: Meeting, _ context: BuildContext, now: Date
    ) async throws -> AgendaItem {
        let state = rowState(for: meeting, todaysMeetings: context.todaysMeetings, now: now)
        let recapReady = recapReadyStates.contains(meeting.lifecycleState)
        let threadRef = try await makeThreadRef(
            for: meeting, threadIDsByMeeting: context.threadIDsByMeeting, threadsByID: context.threadsByID,
            meetingRepository: context.meetingRepository)
        let facts = AgendaRowFacts(state: state, recapReady: recapReady, threadRef: threadRef)
        let fact = continuityFact(meeting: meeting, facts: facts, openActions: context.openActions, now: now)
        return AgendaItem(
            meetingID: meeting.meetingID, start: meeting.startedAt, end: meeting.endedAt ?? meeting.startedAt,
            title: meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title,
            thread: threadRef, state: state, recapReady: recapReady, continuityFact: fact,
            colorSlot: meeting.colorSlot, kind: meeting.kind, recurrenceRuleID: meeting.recurrenceRuleID)
    }

    private static func rowState(for meeting: Meeting, todaysMeetings: [Meeting], now: Date) -> AgendaRowState {
        let end = meeting.endedAt ?? meeting.startedAt
        if meeting.startedAt <= now && end >= now { return .live }
        if end < now { return .past }
        let nextMeetingID = todaysMeetings.filter { $0.startedAt > now }.min { $0.startedAt < $1.startedAt }?.meetingID
        return nextMeetingID == meeting.meetingID ? .next : .future
    }

    /// A meeting can now join several threads at once — the agenda row
    /// still shows only one badge, so this picks the first of
    /// `threadIDsByMeeting`'s pre-ranked (most-recently-touched-first)
    /// list, same tie-break `Self.invertAndRank` establishes once for
    /// every other single-thread-badge spot in this file.
    private static func makeThreadRef(
        for meeting: Meeting, threadIDsByMeeting: [MeetingID: [NSPThreadID]],
        threadsByID: [NSPThreadID: NSPThread], meetingRepository: any MeetingRepository
    ) async throws -> ThreadRef? {
        guard let threadID = threadIDsByMeeting[meeting.meetingID]?.first, let thread = threadsByID[threadID] else {
            return nil
        }
        let siblings = try await meetingRepository.fetchAll(threadID: threadID).sorted { $0.startedAt < $1.startedAt }
        let ordinal = siblings.firstIndex(where: { $0.meetingID == meeting.meetingID }).map { $0 + 1 }
        return ThreadRef(threadID: threadID, name: thread.title, colorSlot: thread.colorSlot, ordinal: ordinal)
    }

    /// Priority order per §4.2: recap ready > up next > carried items >
    /// thread ordinal > fallback. Cross-thread-dependency and
    /// location/attendee facts are omitted rather than fabricated — this
    /// app has no calendar-location or cross-thread-dependency data yet.
    private static func continuityFact(
        meeting: Meeting, facts: AgendaRowFacts, openActions: [Action], now: Date
    ) -> String {
        switch meeting.kind {
        case .notesOnly: return "Meeting with Notes"
        case .recorded: break
        }
        if facts.state == .past, facts.recapReady { return "Recap ready" }
        if facts.state == .next {
            let minutes = max(0, Int(meeting.startedAt.timeIntervalSince(now) / 60))
            return "Up next · in \(minutes) min"
        }
        if let threadRef = facts.threadRef {
            let carried = openActions.filter { $0.meetingID == meeting.meetingID }.count
            if carried > 0, let ordinal = threadRef.ordinal {
                return "\(ordinal.ordinalString) · \(carried) carried item\(carried == 1 ? "" : "s")"
            }
            if let ordinal = threadRef.ordinal {
                return "\(ordinal.ordinalString) of \(threadRef.name)"
            }
        }
        return "Meets \(meeting.startedAt.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))"
    }

    // MARK: - Next Up

    private static func makeNextUp(
        agenda: [AgendaItem], context: BuildContext, now: Date
    ) async throws -> NextUpBrief? {
        guard let upcoming = agenda.first(where: { $0.state == .next || $0.state == .live }) else { return nil }
        let minutes = max(0, Int(upcoming.start.timeIntervalSince(now) / 60))
        let owed = context.openActions.filter { $0.meetingID == upcoming.meetingID && $0.direction == .iOwe }
            .sorted { age($0, now: now) > age($1, now: now) }
        var prepRows: [PrepRow] = []
        if let first = owed.first {
            let ageDays = Int(age(first, now: now) / 86400)
            prepRows.append(
                PrepRow(
                    kind: .owed, leadClause: "You still owe them", body: "\(first.text) — open \(ageDays)d",
                    sourceMeetingID: upcoming.meetingID, source: first.evidence.first))
        }

        var timeline: [ThreadMilestone] = []
        if let threadID = upcoming.thread?.threadID {
            let siblings =
                try await context.meetingRepository.fetchAll(threadID: threadID).sorted { $0.startedAt < $1.startedAt }
            timeline = siblings.suffix(5).map { sibling in
                ThreadMilestone(
                    meetingID: sibling.meetingID, date: sibling.startedAt,
                    phaseLabel: sibling.startedAt.formatted(.dateTime.month(.abbreviated).day()).uppercased(),
                    outcome: nil, isToday: sibling.meetingID == upcoming.meetingID)
            }
        }

        return NextUpBrief(
            meeting: upcoming, minutesUntil: minutes, participants: [],
            countdownFact: upcoming.thread.flatMap { context.threadsByID[$0.threadID]?.externalOrgID },
            prepRows: prepRows, threadTimeline: timeline)
    }

    // MARK: - Needs You / Captured today

    private static func makeNeedsYou(
        openActions: [Action], allMeetings: [Meeting], threadsByID: [NSPThreadID: NSPThread], now: Date
    ) -> NeedsYou {
        let owed = openActions.filter { $0.direction == .iOwe }
        let overdue = owed.filter { age($0, now: now) > 0 }
        let ranked = owed.sorted { age($0, now: now) > age($1, now: now) }
        let titles = Dictionary(uniqueKeysWithValues: allMeetings.map { ($0.meetingID, $0.title) })
        let items = ranked.prefix(3).map { action -> NeedsYouItem in
            let actionAge = age(action, now: now)
            let label =
                actionAge > 0 ? "\(max(1, Int(actionAge / 86400)))d overdue" : Self.statusLabel(action.status)
            return NeedsYouItem(
                actionID: action.actionID, text: action.text,
                provenance: Self.provenance(for: action, titles: titles, threadsByID: threadsByID),
                statusChipLabel: label, isOverdue: actionAge > 0)
        }
        return NeedsYou(items: Array(items), openCount: owed.count, overdueCount: overdue.count)
    }

    /// A thread that's gone quiet — no meeting, decision, or action touch
    /// in 14+ days — surfaced as a `.dormantThread` signal ("The Spine"
    /// recommendation, 2026-08-22: this field existed but nothing ever
    /// populated it). Same 14-day threshold `WeeklyBriefComposer` uses for
    /// its own "threads gone quiet" section, so the two never disagree
    /// about what counts as quiet.
    private static let dormantThreshold: TimeInterval = 14 * 86400

    private static func makeSignals(
        threads: [NSPThread], derivedStatuses: [NSPThreadID: NSPThreadStatus], now: Date
    ) -> [DashboardSignal] {
        threads
            .filter { (derivedStatuses[$0.threadID] ?? $0.status) != .closed }
            .compactMap { thread -> (quietDays: Int, signal: DashboardSignal)? in
                let quietSeconds = now.timeIntervalSince(thread.lastTouchedAt)
                guard quietSeconds >= dormantThreshold else { return nil }
                let quietDays = Int(quietSeconds / 86400)
                let signal = DashboardSignal(
                    kind: .dormantThread, severity: quietDays >= 30 ? .high : .normal,
                    leadClause: "\(thread.title) has gone quiet", body: "No activity in \(quietDays) days")
                return (quietDays, signal)
            }
            .sorted { $0.quietDays > $1.quietDays }
            .map(\.signal)
    }

    /// A meeting-tied action names its meeting; a freestanding one names
    /// its thread instead, if it has one; otherwise there's nothing true
    /// to attribute it to, so the line is just empty (docs/07 §11: never
    /// fabricate a provenance line).
    private static func provenance(
        for action: Action, titles: [MeetingID: String], threadsByID: [NSPThreadID: NSPThread]
    ) -> String {
        if let meetingID = action.meetingID, let title = titles[meetingID] {
            return "From \(title)"
        }
        if let threadID = action.threadID, let thread = threadsByID[threadID] {
            return "From \(thread.title)"
        }
        return ""
    }

    private static func statusLabel(_ status: ActionStatus) -> String {
        switch status {
        case .proposed: return "Proposed"
        case .confirmed: return "Confirmed"
        case .sent: return "Sent"
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        }
    }

    private static func makeCapturedToday(
        todaysMeetings: [Meeting], threadIDsByMeeting: [MeetingID: [NSPThreadID]],
        threadsByID: [NSPThreadID: NSPThread]
    ) -> [RecapCard] {
        todaysMeetings
            .filter { recapReadyStates.contains($0.lifecycleState) }
            .sorted { $0.startedAt > $1.startedAt }
            .map { meeting in
                let threadRef = threadIDsByMeeting[meeting.meetingID]?.first.flatMap { id in
                    threadsByID[id].map { ThreadRef(threadID: id, name: $0.title, colorSlot: $0.colorSlot) }
                }
                let minutes = meeting.endedAt.map { Int($0.timeIntervalSince(meeting.startedAt) / 60) } ?? 0
                return RecapCard(
                    meetingID: meeting.meetingID, thread: threadRef, title: meeting.title,
                    startedAt: meeting.startedAt, durationMinutes: minutes, headline: "", actionsCount: 0,
                    decisionsCount: 0, loopingTopic: nil)
            }
    }

    // MARK: - Helpers

    // Not `private` — `DashboardComposer+Threads.swift`'s
    // `deriveThreadStatuses` calls this too.
    static func age(_ action: Action, now: Date) -> TimeInterval {
        switch action.date {
        case .explicit(let date), .inferred(let date): return now.timeIntervalSince(date)
        case .unresolved: return -.infinity
        }
    }
}

extension Int {
    fileprivate var ordinalString: String {
        let suffix: String
        switch (self % 100, self % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(self)\(suffix)"
    }
}
