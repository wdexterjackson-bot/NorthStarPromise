import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `decision`/`decision_alternative`/`decision_audit_entry`
/// tables (`Migration001InitialSchema`'s original schema — the table
/// existed well before anything wrote to it). Same shape as `ActionRow`:
/// `Decision.evidence` round-trips through the shared `evidence_span`
/// table via `EvidenceSpanPersistence`, not this type.
struct DecisionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "decision"

    var decisionID: String
    var meetingID: String
    var threadID: String?
    var text: String
    var approverState: String
    var approverPersonID: String?
    var status: String
    var rationale: String?
    var supersedes: String?
    var deferCount: Int
    var decideBy: Date?
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case decisionID = "decision_id"
        case meetingID = "meeting_id"
        case threadID = "thread_id"
        case text
        case approverState = "approver_state"
        case approverPersonID = "approver_person_id"
        case status
        case rationale
        case supersedes
        case deferCount = "defer_count"
        case decideBy = "decide_by"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(decision: Decision, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.decisionID = decision.decisionID.rawValue.uuidString
        self.meetingID = decision.meetingID.rawValue.uuidString
        self.threadID = decision.threadID?.rawValue.uuidString
        self.text = decision.text
        switch decision.approver {
        case .explicit(let personID):
            self.approverState = "explicit"
            self.approverPersonID = personID.rawValue.uuidString
        case .inferred(let personID):
            self.approverState = "inferred"
            self.approverPersonID = personID.rawValue.uuidString
        case .unresolved:
            self.approverState = "unresolved"
            self.approverPersonID = nil
        }
        self.status = decision.status.rawValue
        self.rationale = decision.rationale
        self.supersedes = decision.supersedes?.rawValue.uuidString
        self.deferCount = decision.deferCount
        self.decideBy = decision.decideBy
        self.createdBy = decision.createdBy.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(
        evidence: [EvidenceSpan], alternativesConsidered: [String], auditTrail: [AuditEntry]
    ) throws -> Decision {
        guard let decisionUUID = UUID(uuidString: decisionID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "decision_id", value: decisionID)
        }
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let createdByUUID = UUID(uuidString: createdBy) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "created_by", value: createdBy)
        }
        guard let decisionStatus = DecisionStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }
        let resolvedSupersedes = try supersedes.map { string -> DecisionID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "supersedes", value: string)
            }
            return DecisionID(rawValue: uuid)
        }

        let resolvedThreadID: NSPThreadID? = try threadID.map { string -> NSPThreadID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "thread_id", value: string)
            }
            return NSPThreadID(rawValue: uuid)
        }

        return Decision(
            decisionID: DecisionID(rawValue: decisionUUID), meetingID: MeetingID(rawValue: meetingUUID),
            threadID: resolvedThreadID, text: text,
            approver: try Self.decodeApprover(state: approverState, personID: approverPersonID),
            status: decisionStatus, rationale: rationale, alternativesConsidered: alternativesConsidered,
            supersedes: resolvedSupersedes, deferCount: deferCount, decideBy: decideBy, evidence: evidence,
            createdBy: PersonID(rawValue: createdByUUID), auditTrail: auditTrail)
    }

    private static func decodeApprover(state: String, personID: String?) throws -> ResolvedValue<PersonID> {
        switch state {
        case "unresolved": return .unresolved
        case "explicit", "inferred":
            guard let personID, let uuid = UUID(uuidString: personID) else {
                throw PersistenceError.corruptRow(
                    table: databaseTableName, column: "approver_person_id", value: personID)
            }
            return state == "explicit" ? .explicit(PersonID(rawValue: uuid)) : .inferred(PersonID(rawValue: uuid))
        default:
            throw PersistenceError.corruptRow(table: databaseTableName, column: "approver_state", value: state)
        }
    }
}

/// Mirrors `decision_alternative` — `Decision.alternativesConsidered`.
struct DecisionAlternativeRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "decision_alternative"
    var decisionID: String
    var position: Int
    var text: String

    enum CodingKeys: String, CodingKey {
        case decisionID = "decision_id"
        case position
        case text
    }
}

/// Mirrors `decision_audit_entry` — `Decision.auditTrail`, same shape as
/// `ActionAuditEntryRow`.
struct DecisionAuditEntryRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "decision_audit_entry"

    var id: Int64?
    var decisionID: String
    var position: Int
    var actorID: String
    var actionText: String
    var at: Date
    var detail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case decisionID = "decision_id"
        case position
        case actorID = "actor_id"
        case actionText = "action_text"
        case at
        case detail
    }

    init(decisionID: String, position: Int, entry: AuditEntry) {
        self.id = nil
        self.decisionID = decisionID
        self.position = position
        self.actorID = entry.actorID.rawValue.uuidString
        self.actionText = entry.action
        self.at = entry.at
        self.detail = entry.detail
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() throws -> AuditEntry {
        guard let actorUUID = UUID(uuidString: actorID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "actor_id", value: actorID)
        }
        return AuditEntry(actorID: PersonID(rawValue: actorUUID), action: actionText, at: at, detail: detail)
    }
}
