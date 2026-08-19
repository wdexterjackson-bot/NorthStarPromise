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
    public let meetingID: MeetingID

    /// Verb-first, editable; retains the original extracted phrase.
    public var text: String
    public var owner: ResolvedValue<PersonID>
    public var date: ResolvedValue<Date>
    public var status: ActionStatus
    public var dependencies: [ActionID]
    public var destination: String?

    public let evidence: [EvidenceSpan]
    public let createdBy: PersonID
    public var confirmedBy: PersonID?
    public var auditTrail: [AuditEntry]

    public init(
        actionID: ActionID,
        meetingID: MeetingID,
        text: String,
        owner: ResolvedValue<PersonID> = .unresolved,
        date: ResolvedValue<Date> = .unresolved,
        status: ActionStatus = .proposed,
        dependencies: [ActionID] = [],
        destination: String? = nil,
        evidence: [EvidenceSpan],
        createdBy: PersonID,
        confirmedBy: PersonID? = nil,
        auditTrail: [AuditEntry] = []
    ) {
        self.actionID = actionID
        self.meetingID = meetingID
        self.text = text
        self.owner = owner
        self.date = date
        self.status = status
        self.dependencies = dependencies
        self.destination = destination
        self.evidence = evidence
        self.createdBy = createdBy
        self.confirmedBy = confirmedBy
        self.auditTrail = auditTrail
    }
}
