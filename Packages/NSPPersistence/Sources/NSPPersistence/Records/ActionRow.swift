import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `action_item` table (docs/02 §5, named `action_item` rather
/// than `action` — see the migration's comment on why). `Action.evidence`
/// round-trips through the shared `evidence_span` table via
/// `EvidenceSpanPersistence` (`GRDBActionRepository` calls it, not this
/// type — `asDomain` here takes evidence as a parameter the same way it
/// already takes `auditTrail`). `Action.dependencies` still isn't
/// round-tripped: nothing in this codebase sets one yet — a documented
/// scope cut, not silent data loss.
struct ActionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_item"

    var actionID: String
    var workspaceID: String
    var meetingID: String?
    var threadID: String?
    var counterpartyID: String?
    var text: String
    var ownerState: String
    var ownerPersonID: String?
    var dateState: String
    var dateValue: Date?
    var status: String
    var destination: String?
    var direction: String
    var deferCount: Int
    var askedAgainCount: Int
    var confidence: Double
    var edited: Bool
    var createdBy: String
    var confirmedBy: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case workspaceID = "workspace_id"
        case meetingID = "meeting_id"
        case threadID = "thread_id"
        case counterpartyID = "counterparty_id"
        case text
        case ownerState = "owner_state"
        case ownerPersonID = "owner_person_id"
        case dateState = "date_state"
        case dateValue = "date_value"
        case status
        case destination
        case direction
        case deferCount = "defer_count"
        case askedAgainCount = "asked_again_count"
        case confidence
        case edited
        case createdBy = "created_by"
        case confirmedBy = "confirmed_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(action: Action, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.actionID = action.actionID.rawValue.uuidString
        self.workspaceID = action.workspaceID.rawValue.uuidString
        self.meetingID = action.meetingID?.rawValue.uuidString
        self.threadID = action.threadID?.rawValue.uuidString
        self.counterpartyID = action.counterpartyID?.rawValue.uuidString
        self.text = action.text
        switch action.owner {
        case .explicit(let personID):
            self.ownerState = "explicit"
            self.ownerPersonID = personID.rawValue.uuidString
        case .inferred(let personID):
            self.ownerState = "inferred"
            self.ownerPersonID = personID.rawValue.uuidString
        case .unresolved:
            self.ownerState = "unresolved"
            self.ownerPersonID = nil
        }
        switch action.date {
        case .explicit(let date):
            self.dateState = "explicit"
            self.dateValue = date
        case .inferred(let date):
            self.dateState = "inferred"
            self.dateValue = date
        case .unresolved:
            self.dateState = "unresolved"
            self.dateValue = nil
        }
        self.status = action.status.rawValue
        self.destination = action.destination
        self.direction = action.direction.rawValue
        self.deferCount = action.deferCount
        self.askedAgainCount = action.askedAgainCount
        self.confidence = action.confidence
        self.edited = action.edited
        self.createdBy = action.createdBy.rawValue.uuidString
        self.confirmedBy = action.confirmedBy?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(evidence: [EvidenceSpan], auditTrail: [AuditEntry]) throws -> Action {
        guard let actionUUID = UUID(uuidString: actionID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "action_id", value: actionID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let createdByUUID = UUID(uuidString: createdBy) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "created_by", value: createdBy)
        }
        guard let actionStatus = ActionStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }
        guard let commitmentDirection = CommitmentDirection(rawValue: direction) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "direction", value: direction)
        }

        return Action(
            actionID: ActionID(rawValue: actionUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID),
            meetingID: try Self.decodeUUID(meetingID, column: "meeting_id").map { MeetingID(rawValue: $0) },
            threadID: try Self.decodeUUID(threadID, column: "thread_id").map { NSPThreadID(rawValue: $0) },
            counterpartyID: try Self.decodeUUID(counterpartyID, column: "counterparty_id").map {
                PersonID(rawValue: $0)
            }, text: text,
            owner: try Self.decodeOwner(state: ownerState, personID: ownerPersonID),
            date: try Self.decodeDate(state: dateState, value: dateValue), status: actionStatus,
            destination: destination, direction: commitmentDirection, deferCount: deferCount,
            askedAgainCount: askedAgainCount, confidence: confidence, edited: edited, evidence: evidence,
            createdBy: PersonID(rawValue: createdByUUID),
            confirmedBy: try Self.decodeUUID(confirmedBy, column: "confirmed_by").map { PersonID(rawValue: $0) },
            auditTrail: auditTrail)
    }

    /// Decodes an optional UUID-string column, `nil` in and `nil` out —
    /// `meeting_id`/`thread_id`/`counterparty_id`/`confirmed_by` all share
    /// this exact shape now that `meeting_id` is nullable too.
    private static func decodeUUID(_ value: String?, column: String) throws -> UUID? {
        guard let value else { return nil }
        guard let uuid = UUID(uuidString: value) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: column, value: value)
        }
        return uuid
    }

    private static func decodeOwner(state: String, personID: String?) throws -> ResolvedValue<PersonID> {
        switch state {
        case "unresolved": return .unresolved
        case "explicit", "inferred":
            guard let personID, let uuid = UUID(uuidString: personID) else {
                throw PersistenceError.corruptRow(table: databaseTableName, column: "owner_person_id", value: personID)
            }
            return state == "explicit" ? .explicit(PersonID(rawValue: uuid)) : .inferred(PersonID(rawValue: uuid))
        default:
            throw PersistenceError.corruptRow(table: databaseTableName, column: "owner_state", value: state)
        }
    }

    private static func decodeDate(state: String, value: Date?) throws -> ResolvedValue<Date> {
        switch state {
        case "unresolved": return .unresolved
        case "explicit", "inferred":
            guard let value else {
                throw PersistenceError.corruptRow(table: databaseTableName, column: "date_value", value: nil)
            }
            return state == "explicit" ? .explicit(value) : .inferred(value)
        default:
            throw PersistenceError.corruptRow(table: databaseTableName, column: "date_state", value: state)
        }
    }
}

/// Mirrors the `action_audit_entry` table — one row per `Action.auditTrail`
/// entry, ordered by `position` (`AuditEntry` itself carries no ordinal).
struct ActionAuditEntryRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_audit_entry"

    var id: Int64?
    var actionID: String
    var position: Int
    var actorID: String
    var actionText: String
    var at: Date
    var detail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case actionID = "action_id"
        case position
        case actorID = "actor_id"
        case actionText = "action_text"
        case at
        case detail
    }

    init(actionID: String, position: Int, entry: AuditEntry) {
        self.id = nil
        self.actionID = actionID
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
