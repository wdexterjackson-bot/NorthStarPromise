import Foundation

/// One audit entry on an `Action` or `Decision`'s history — creator, confirmer,
/// edits, and export attempts with their responses (docs/02 §2, "Audit" row).
public struct AuditEntry: Sendable, Hashable, Codable {
    public let actorID: PersonID
    public let action: String
    public let at: Date
    public let detail: String?

    public init(actorID: PersonID, action: String, at: Date, detail: String? = nil) {
        self.actorID = actorID
        self.action = action
        self.at = at
        self.detail = detail
    }
}

/// One follow-through commitment (docs/02 §2). Cannot leave `.proposed`
/// without at least one evidence span and explicit human confirmation
/// (Invariant I6).
public struct Action: Sendable, Hashable, Codable, Identifiable {
    public let actionID: ActionID
    public var id: ActionID { actionID }
    public let workspaceID: WorkspaceID
    /// `nil` for a freestanding action — one the user can act on themselves
    /// without it being extracted from, or tied to, a specific recording
    /// (the user's own distinction: an action item is something they can
    /// control directly, unlike a `Thread`, which needs coordinated effort
    /// across several meetings/emails/people). Required to have a
    /// `workspaceID` regardless, since "Needs You" and every other
    /// workspace-scoped list still needs to find it.
    public var meetingID: MeetingID?
    /// The storyline this action's commitment threads through, if any —
    /// independent of `meetingID`: a freestanding action can carry a
    /// `threadID` with no meeting at all, and a meeting-tied action can
    /// belong to a thread its meeting doesn't (or vice versa).
    public var threadID: NSPThreadID?
    /// Who this commitment is with — lets People answer "what do I owe
    /// this specific person" as a real filtered query instead of guessing
    /// from meeting attendees.
    public var counterpartyID: PersonID?

    /// Verb-first, editable; retains the original extracted phrase.
    public var text: String
    public var owner: ResolvedValue<PersonID>
    public var date: ResolvedValue<Date>
    public var status: ActionStatus
    public var dependencies: [ActionID]
    public var destination: String?

    /// The Dashboard's commitment-ledger fields (`DASHBOARD_SPEC.md` §3.4),
    /// extended onto `Action` rather than a parallel `Commitment` type
    /// (Dashboard scope plan's explicit default). All default to the
    /// "nothing extracted yet" state so every existing `Action` stays
    /// valid; Phase 5's real extraction pipeline is what populates them
    /// meaningfully.
    public var direction: CommitmentDirection
    /// How many times this action has been reconfirmed without being
    /// completed — what makes "Deferred 3 times" truthful once dedup
    /// (deferred to Phase 5) increments it instead of duplicating rows.
    public var deferCount: Int
    /// How many times the counterparty has re-raised an item the user owes
    /// them — licenses "Rachel has asked twice since."
    public var askedAgainCount: Int
    /// Extraction confidence, 0...1. Below 0.7 an item is stored but never
    /// promoted to the Dashboard (spec §3.4) — hand-created/edited actions
    /// default to 1.0, i.e. always trusted.
    public var confidence: Double
    public var edited: Bool

    public let evidence: [EvidenceSpan]
    public let createdBy: PersonID
    public var confirmedBy: PersonID?
    public var auditTrail: [AuditEntry]

    public init(
        actionID: ActionID,
        workspaceID: WorkspaceID,
        meetingID: MeetingID? = nil,
        threadID: NSPThreadID? = nil,
        counterpartyID: PersonID? = nil,
        text: String,
        owner: ResolvedValue<PersonID> = .unresolved,
        date: ResolvedValue<Date> = .unresolved,
        status: ActionStatus = .proposed,
        dependencies: [ActionID] = [],
        destination: String? = nil,
        direction: CommitmentDirection = .iOwe,
        deferCount: Int = 0,
        askedAgainCount: Int = 0,
        confidence: Double = 1.0,
        edited: Bool = false,
        evidence: [EvidenceSpan],
        createdBy: PersonID,
        confirmedBy: PersonID? = nil,
        auditTrail: [AuditEntry] = []
    ) {
        self.actionID = actionID
        self.workspaceID = workspaceID
        self.meetingID = meetingID
        self.threadID = threadID
        self.counterpartyID = counterpartyID
        self.text = text
        self.owner = owner
        self.date = date
        self.status = status
        self.dependencies = dependencies
        self.destination = destination
        self.direction = direction
        self.deferCount = deferCount
        self.askedAgainCount = askedAgainCount
        self.confidence = confidence
        self.edited = edited
        self.evidence = evidence
        self.createdBy = createdBy
        self.confirmedBy = confirmedBy
        self.auditTrail = auditTrail
    }
}
