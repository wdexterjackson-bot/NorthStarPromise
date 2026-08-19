/// One recorded decision, with the reasoning behind it (docs/02 §2).
public struct Decision: Sendable, Hashable, Codable, Identifiable {
    public let decisionID: DecisionID
    public var id: DecisionID { decisionID }
    public let meetingID: MeetingID

    public var text: String
    public var approver: ResolvedValue<PersonID>
    public var status: DecisionStatus
    public var rationale: String?
    public var alternativesConsidered: [String]
    /// The decision this one replaces, forming a supersession chain.
    public var supersedes: DecisionID?

    public let evidence: [EvidenceSpan]
    public let createdBy: PersonID
    public var auditTrail: [AuditEntry]

    public init(
        decisionID: DecisionID,
        meetingID: MeetingID,
        text: String,
        approver: ResolvedValue<PersonID> = .unresolved,
        status: DecisionStatus = .proposed,
        rationale: String? = nil,
        alternativesConsidered: [String] = [],
        supersedes: DecisionID? = nil,
        evidence: [EvidenceSpan],
        createdBy: PersonID,
        auditTrail: [AuditEntry] = []
    ) {
        self.decisionID = decisionID
        self.meetingID = meetingID
        self.text = text
        self.approver = approver
        self.status = status
        self.rationale = rationale
        self.alternativesConsidered = alternativesConsidered
        self.supersedes = supersedes
        self.evidence = evidence
        self.createdBy = createdBy
        self.auditTrail = auditTrail
    }
}
