import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the append-only `audit_event` table (docs/06 §11: "Append-only,
/// admin-exportable; deleting content never deletes the audit trail") — no
/// `updated_at`/`row_revision`, rows are never mutated after insert.
struct AuditEventRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "audit_event"

    var auditEventID: String
    var actorID: String?
    var action: String
    var object: String
    var payloadHash: String
    var result: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case auditEventID = "audit_event_id"
        case actorID = "actor_id"
        case action
        case object
        case payloadHash = "payload_hash"
        case result
        case timestamp
    }

    init(event: AuditEvent) {
        self.auditEventID = event.auditEventID.rawValue.uuidString
        self.actorID = event.actorID?.rawValue.uuidString
        self.action = event.action
        self.object = event.object
        self.payloadHash = event.payloadHash
        self.result = event.result.rawValue
        self.timestamp = event.timestamp
    }

    func asDomain() throws -> AuditEvent {
        guard let eventUUID = UUID(uuidString: auditEventID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "audit_event_id", value: auditEventID)
        }
        guard let auditResult = AuditResult(rawValue: result) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "result", value: result)
        }
        let actor = actorID.flatMap(UUID.init(uuidString:)).map(PersonID.init(rawValue:))

        return AuditEvent(
            auditEventID: AuditEventID(rawValue: eventUUID),
            actorID: actor,
            action: action,
            object: object,
            payloadHash: payloadHash,
            result: auditResult,
            timestamp: timestamp
        )
    }
}
