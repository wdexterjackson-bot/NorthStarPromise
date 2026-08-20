import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `action_item` table (docs/02 §5, named `action_item` rather
/// than `action` — see the migration's comment on why). `Action.evidence`
/// and `Action.dependencies` aren't round-tripped here: nothing in this
/// codebase produces an `EvidenceSpan` yet (that needs a transcript
/// pipeline `NSPIntelligence` doesn't have) or sets a dependency, so every
/// `Action` built by `ActionRepository` carries `evidence: []` and
/// `dependencies: []`. This is a documented scope cut, not silent data
/// loss — nothing here ever receives a non-empty value to drop.
struct ActionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_item"

    var actionID: String
    var meetingID: String
    var text: String
    var ownerState: String
    var ownerPersonID: String?
    var dateState: String
    var dateValue: Date?
    var status: String
    var destination: String?
    var createdBy: String
    var confirmedBy: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case meetingID = "meeting_id"
        case text
        case ownerState = "owner_state"
        case ownerPersonID = "owner_person_id"
        case dateState = "date_state"
        case dateValue = "date_value"
        case status
        case destination
        case createdBy = "created_by"
        case confirmedBy = "confirmed_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(action: Action, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.actionID = action.actionID.rawValue.uuidString
        self.meetingID = action.meetingID.rawValue.uuidString
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
        self.createdBy = action.createdBy.rawValue.uuidString
        self.confirmedBy = action.confirmedBy?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(auditTrail: [AuditEntry]) throws -> Action {
        guard let actionUUID = UUID(uuidString: actionID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "action_id", value: actionID)
        }
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let createdByUUID = UUID(uuidString: createdBy) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "created_by", value: createdBy)
        }
        guard let actionStatus = ActionStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }

        return Action(
            actionID: ActionID(rawValue: actionUUID), meetingID: MeetingID(rawValue: meetingUUID), text: text,
            owner: try Self.decodeOwner(state: ownerState, personID: ownerPersonID),
            date: try Self.decodeDate(state: dateState, value: dateValue), status: actionStatus,
            destination: destination, evidence: [], createdBy: PersonID(rawValue: createdByUUID),
            confirmedBy: try confirmedBy.map { string -> PersonID in
                guard let uuid = UUID(uuidString: string) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "confirmed_by", value: string)
                }
                return PersonID(rawValue: uuid)
            }, auditTrail: auditTrail)
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
