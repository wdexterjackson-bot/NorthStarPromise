import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `consent_record` table (docs/02 §2). `participantsAcknowledged`
/// lives in its own child table (`consent_record_participant`) since it's an
/// array, same shape `PolicyRow` uses for `blockedDomains`/`blockedLocations`.
struct ConsentRecordRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "consent_record"

    var consentRecordID: String
    var meetingID: String
    var method: String
    var timestamp: Date
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case consentRecordID = "consent_record_id"
        case meetingID = "meeting_id"
        case method
        case timestamp
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(record: ConsentRecord, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.consentRecordID = record.consentRecordID.rawValue.uuidString
        self.meetingID = record.meetingID.rawValue.uuidString
        self.method = record.method.rawValue
        self.timestamp = record.timestamp
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(participantsAcknowledged: [PersonID]) throws -> ConsentRecord {
        guard let recordUUID = UUID(uuidString: consentRecordID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "consent_record_id", value: consentRecordID)
        }
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let consentMethod = ConsentMethod(rawValue: method) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "method", value: method)
        }

        return ConsentRecord(
            consentRecordID: ConsentRecordID(rawValue: recordUUID),
            meetingID: MeetingID(rawValue: meetingUUID),
            method: consentMethod,
            timestamp: timestamp,
            participantsAcknowledged: participantsAcknowledged
        )
    }
}

/// Mirrors `consent_record_participant` — the exploded form of
/// `ConsentRecord.participantsAcknowledged`.
struct ConsentRecordParticipantRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "consent_record_participant"
    var consentRecordID: String
    var personID: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case consentRecordID = "consent_record_id"
        case personID = "person_id"
        case position
    }
}
