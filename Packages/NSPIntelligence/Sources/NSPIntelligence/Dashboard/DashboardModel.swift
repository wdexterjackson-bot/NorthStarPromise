import Foundation
import NSPCore

/// The Dashboard's single composed model (`DASHBOARD_SPEC.md` §6) — both
/// iPhone and iPad render pure functions of this one value, so the two
/// builds can't drift apart. Plain data only: no `NSPDesignSystem` types
/// here (that package sits below `NSPIntelligence` in the dependency
/// direction — CLAUDE.md §3 — so the View layer maps `colorSlot`/`PersonRef`
/// into `Palette`/`AvatarRef` at render time, not this model).
public struct DashboardModel: Equatable, Sendable {
    public let date: Date
    /// `"6 meetings · 4 threads in motion"`.
    public let headline: String
    /// Total meetings ever recorded — the Recall placeholder's live count.
    public let corpusCount: Int
    /// Every one of today's meetings, chronological — never pre-filtered.
    public let agenda: [AgendaItem]
    /// `nil` once the day's last meeting has passed.
    public let nextUp: NextUpBrief?
    /// Ranked, capped at 3 (iPad) / shown in full on the dedicated tab.
    public let threadsInMotion: [ThreadCard]
    public let needsYou: NeedsYou
    /// Ranked, capped at 3 (iPad) / 2 (iPhone). Empty when nothing
    /// qualifies — signals are omitted entirely, never padded (§8.1).
    public let signals: [DashboardSignal]
    /// Today's meetings with a recap ready, newest first.
    public let capturedToday: [RecapCard]
    public let navCounts: NavCounts

    public init(
        date: Date, headline: String, corpusCount: Int, agenda: [AgendaItem], nextUp: NextUpBrief?,
        threadsInMotion: [ThreadCard], needsYou: NeedsYou, signals: [DashboardSignal], capturedToday: [RecapCard],
        navCounts: NavCounts
    ) {
        self.date = date
        self.headline = headline
        self.corpusCount = corpusCount
        self.agenda = agenda
        self.nextUp = nextUp
        self.threadsInMotion = threadsInMotion
        self.needsYou = needsYou
        self.signals = signals
        self.capturedToday = capturedToday
        self.navCounts = navCounts
    }
}

/// Which storyline an agenda row/card belongs to — plain data the View
/// layer resolves to a color via `Palette.threadSlots[colorSlot]`.
public struct ThreadRef: Equatable, Sendable {
    public let threadID: NSPThreadID
    public let name: String
    public let colorSlot: Int
    /// "6th meeting" — nil when the ordinal isn't known/meaningful.
    public let ordinal: Int?

    public init(threadID: NSPThreadID, name: String, colorSlot: Int, ordinal: Int? = nil) {
        self.threadID = threadID
        self.name = name
        self.colorSlot = colorSlot
        self.ordinal = ordinal
    }
}

/// Where an agenda row sits relative to now — drives the row-state styling
/// table in `DASHBOARD_SPEC.md` §4.2/§5.4.
public enum AgendaRowState: Sendable, Equatable {
    case past
    case live
    case next
    case future
}

public struct AgendaItem: Identifiable, Equatable, Sendable {
    public var id: MeetingID { meetingID }
    public let meetingID: MeetingID
    public let start: Date
    public let end: Date
    public let title: String
    public let thread: ThreadRef?
    public let state: AgendaRowState
    public let recapReady: Bool
    /// The pre-selected sub-line text, already resolved per the priority
    /// order in §4.2 ("Recap ready" > "Up next" > carried items > thread
    /// ordinal > cross-thread dependency > attendee/location fallback) —
    /// **this is the point of the row** (spec's own words); a row without
    /// one is a bug, not a style choice.
    public let continuityFact: String
    public let joinURL: URL?

    public init(
        meetingID: MeetingID, start: Date, end: Date, title: String, thread: ThreadRef?, state: AgendaRowState,
        recapReady: Bool, continuityFact: String, joinURL: URL? = nil
    ) {
        self.meetingID = meetingID
        self.start = start
        self.end = end
        self.title = title
        self.thread = thread
        self.state = state
        self.recapReady = recapReady
        self.continuityFact = continuityFact
        self.joinURL = joinURL
    }
}

public struct PersonRef: Identifiable, Equatable, Sendable {
    public var id: PersonID { personID }
    public let personID: PersonID
    public let displayName: String
    public let initials: String

    public init(personID: PersonID, displayName: String, initials: String) {
        self.personID = personID
        self.displayName = displayName
        self.initials = initials
    }
}

/// One "carried in from your history" row on the Next Up card (§4.4/§5.3).
public struct PrepRow: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case owed, unresolved, expectAgain
    }

    public let kind: Kind
    /// Rendered at 800 weight in the kind's semantic color.
    public let leadClause: String
    public let body: String
    public let sourceMeetingID: MeetingID
    /// Deep link into the transcript this row was derived from — reuses
    /// `EvidenceSpan` rather than inventing a parallel `Reference` type
    /// (spec §3.1 wants exactly this: meeting + transcript offset).
    public let source: EvidenceSpan?
    /// Ties this row to the matching entry in `NextUpBrief.threadTimeline`
    /// so the UI can highlight both in the same semantic color.
    public let milestoneID: MeetingID?

    public init(
        kind: Kind, leadClause: String, body: String, sourceMeetingID: MeetingID, source: EvidenceSpan? = nil,
        milestoneID: MeetingID? = nil
    ) {
        self.kind = kind
        self.leadClause = leadClause
        self.body = body
        self.sourceMeetingID = sourceMeetingID
        self.source = source
        self.milestoneID = milestoneID
    }
}

/// One entry in "This thread so far" (iPad's right-hand rail) — a
/// lightweight, computed stand-in for the spec's persisted `Milestone`
/// entity (§3.2), since no recap-generation pipeline exists yet to populate
/// one (Phase 5, deferred). Real data renders one entry per meeting with
/// `outcome == nil`; fixtures populate a real outcome sentence.
public struct ThreadMilestone: Identifiable, Equatable, Sendable {
    public var id: MeetingID { meetingID }
    public let meetingID: MeetingID
    public let date: Date
    public let phaseLabel: String
    public let outcome: String?
    public let isToday: Bool
    public let tiedPrepRowKind: PrepRow.Kind?

    public init(
        meetingID: MeetingID, date: Date, phaseLabel: String, outcome: String?, isToday: Bool,
        tiedPrepRowKind: PrepRow.Kind? = nil
    ) {
        self.meetingID = meetingID
        self.date = date
        self.phaseLabel = phaseLabel
        self.outcome = outcome
        self.isToday = isToday
        self.tiedPrepRowKind = tiedPrepRowKind
    }
}

public struct NextUpBrief: Equatable, Sendable {
    public let meeting: AgendaItem
    public let minutesUntil: Int
    public let participants: [PersonRef]
    /// "Renewal in 41 days" — the thread's hard external deadline, if any.
    public let countdownFact: String?
    /// 0...3, ranked, `owed → unresolved → expectAgain` (§7.6). Never
    /// padded — fewer than three renders fewer.
    public let prepRows: [PrepRow]
    /// Last five meetings + today, oldest first (iPad's right rail only).
    public let threadTimeline: [ThreadMilestone]

    public init(
        meeting: AgendaItem, minutesUntil: Int, participants: [PersonRef], countdownFact: String?,
        prepRows: [PrepRow], threadTimeline: [ThreadMilestone]
    ) {
        self.meeting = meeting
        self.minutesUntil = minutesUntil
        self.participants = participants
        self.countdownFact = countdownFact
        self.prepRows = prepRows
        self.threadTimeline = threadTimeline
    }
}

public struct ThreadCard: Identifiable, Equatable, Sendable {
    public var id: NSPThreadID { threadID }
    public let threadID: NSPThreadID
    public let name: String
    public let colorSlot: Int
    public let status: NSPThreadStatus
    public let meetingCount: Int
    public let sinceDate: Date
    /// The card's one-line "current tension" (`"Valuation floor deferred 3
    /// times. IC votes Monday."`) — `nil` against real data until Phase 5's
    /// signals/derivation pipeline can generate one honestly.
    public let tensionSentence: String?

    public init(
        threadID: NSPThreadID, name: String, colorSlot: Int, status: NSPThreadStatus, meetingCount: Int,
        sinceDate: Date, tensionSentence: String?
    ) {
        self.threadID = threadID
        self.name = name
        self.colorSlot = colorSlot
        self.status = status
        self.meetingCount = meetingCount
        self.sinceDate = sinceDate
        self.tensionSentence = tensionSentence
    }
}

public struct NeedsYouItem: Identifiable, Equatable, Sendable {
    public var id: ActionID { actionID }
    public let actionID: ActionID
    public let text: String
    /// Mandatory provenance line — "where did this come from"
    /// (`"You said it on Jul 30 · Meridian account"`, §4.5).
    public let provenance: String
    public let statusChipLabel: String
    public let isOverdue: Bool

    public init(actionID: ActionID, text: String, provenance: String, statusChipLabel: String, isOverdue: Bool) {
        self.actionID = actionID
        self.text = text
        self.provenance = provenance
        self.statusChipLabel = statusChipLabel
        self.isOverdue = isOverdue
    }
}

public struct NeedsYou: Equatable, Sendable {
    /// Top 3 — the header's own count tells the truth about the rest.
    public let items: [NeedsYouItem]
    public let openCount: Int
    public let overdueCount: Int

    public init(items: [NeedsYouItem], openCount: Int, overdueCount: Int) {
        self.items = items
        self.openCount = openCount
        self.overdueCount = overdueCount
    }
}

/// One "what your history noticed" card (§7.5's signals engine) — the
/// engine itself is deferred to Phase 5; this type exists now so fixtures
/// and the View layer have somewhere to render a signal once it does run.
public struct DashboardSignal: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case unresolvedLoop, collision, personPattern, overdueCommitment, dormantThread
    }
    public enum Severity: Sendable, Equatable {
        case high, normal
    }

    public var id: String { leadClause + body }
    public let kind: Kind
    public let severity: Severity
    public let leadClause: String
    public let body: String

    public init(kind: Kind, severity: Severity, leadClause: String, body: String) {
        self.kind = kind
        self.severity = severity
        self.leadClause = leadClause
        self.body = body
    }
}

public struct RecapCard: Identifiable, Equatable, Sendable {
    public var id: MeetingID { meetingID }
    public let meetingID: MeetingID
    public let thread: ThreadRef?
    public let title: String
    public let startedAt: Date
    public let durationMinutes: Int
    public let headline: String
    public let actionsCount: Int
    public let decisionsCount: Int
    /// A `warn`-styled chip naming an already-looping topic the recap
    /// touched (`"PRICING AGAIN"`) — `nil` when nothing looped.
    public let loopingTopic: String?

    public init(
        meetingID: MeetingID, thread: ThreadRef?, title: String, startedAt: Date, durationMinutes: Int,
        headline: String, actionsCount: Int, decisionsCount: Int, loopingTopic: String?
    ) {
        self.meetingID = meetingID
        self.thread = thread
        self.title = title
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.headline = headline
        self.actionsCount = actionsCount
        self.decisionsCount = decisionsCount
        self.loopingTopic = loopingTopic
    }
}

public struct NavCounts: Equatable, Sendable {
    public let todayMeetings: Int
    public let openThreads: Int
    public let openActionsIOwe: Int
    public let libraryTotal: Int

    public init(todayMeetings: Int, openThreads: Int, openActionsIOwe: Int, libraryTotal: Int) {
        self.todayMeetings = todayMeetings
        self.openThreads = openThreads
        self.openActionsIOwe = openActionsIOwe
        self.libraryTotal = libraryTotal
    }
}
