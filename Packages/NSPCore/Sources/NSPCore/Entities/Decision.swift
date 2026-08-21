import Foundation

/// One recorded decision, with the reasoning behind it (docs/02 §2).
public struct Decision: Sendable, Hashable, Codable, Identifiable {
    public let decisionID: DecisionID
    public var id: DecisionID { decisionID }
    public let meetingID: MeetingID
    /// The storyline this decision threads through, if any — a decision is
    /// always made *in* a specific meeting (unlike `Action`, never
    /// freestanding), but the thread it feeds can still be set/overridden
    /// independently of that meeting's own thread membership.
    public var threadID: NSPThreadID?

    public var text: String
    public var approver: ResolvedValue<PersonID>
    public var status: DecisionStatus
    public var rationale: String?
    public var alternativesConsidered: [String]
    /// The decision this one replaces, forming a supersession chain.
    public var supersedes: DecisionID?

    /// How many times this decision has been parked/reconfirmed without
    /// resolving — feeds `NSPThreadStatus.decisionDue` (`deferCount >= 2`,
    /// `DASHBOARD_SPEC.md` §3.2).
    public var deferCount: Int
    /// A hard date this decision is due by, if known — the other
    /// `decisionDue` trigger ("inside 5 days").
    public var decideBy: Date?

    public let evidence: [EvidenceSpan]
    public let createdBy: PersonID
    public var auditTrail: [AuditEntry]

    public init(
        decisionID: DecisionID,
        meetingID: MeetingID,
        threadID: NSPThreadID? = nil,
        text: String,
        approver: ResolvedValue<PersonID> = .unresolved,
        status: DecisionStatus = .proposed,
        rationale: String? = nil,
        alternativesConsidered: [String] = [],
        supersedes: DecisionID? = nil,
        deferCount: Int = 0,
        decideBy: Date? = nil,
        evidence: [EvidenceSpan],
        createdBy: PersonID,
        auditTrail: [AuditEntry] = []
    ) {
        self.decisionID = decisionID
        self.meetingID = meetingID
        self.threadID = threadID
        self.text = text
        self.approver = approver
        self.status = status
        self.rationale = rationale
        self.alternativesConsidered = alternativesConsidered
        self.supersedes = supersedes
        self.deferCount = deferCount
        self.decideBy = decideBy
        self.evidence = evidence
        self.createdBy = createdBy
        self.auditTrail = auditTrail
    }
}
