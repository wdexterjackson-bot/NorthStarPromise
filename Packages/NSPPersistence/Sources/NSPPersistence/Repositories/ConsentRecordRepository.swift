import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `ConsentRecord`, plus the existence check `NSPPolicy`'s
/// `ConsentRecordLookup` adapter needs (`NetworkGate.authorize`'s
/// `EgressDenial.noConsentRecord` check).
public protocol ConsentRecordRepository: Sendable {
    func insert(_ record: ConsentRecord, at date: Date) async throws
    func find(_ id: ConsentRecordID) async throws -> ConsentRecord?
    func hasRecord(forMeetingID meetingID: MeetingID) async throws -> Bool
}

public struct GRDBConsentRecordRepository: ConsentRecordRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ record: ConsentRecord, at date: Date) async throws {
        let row = ConsentRecordRow(record: record, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.syncParticipants(db, consentRecordID: row.consentRecordID, record: record)
        }
    }

    public func find(_ id: ConsentRecordID) async throws -> ConsentRecord? {
        try await dbWriter.read { db in
            try Self.fetchRecord(db, consentRecordID: id.rawValue.uuidString)
        }
    }

    public func hasRecord(forMeetingID meetingID: MeetingID) async throws -> Bool {
        try await dbWriter.read { db in
            try ConsentRecordRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .fetchCount(db) > 0
        }
    }

    // MARK: - Helpers

    private static func fetchRecord(_ db: Database, consentRecordID: String) throws -> ConsentRecord? {
        guard let row = try ConsentRecordRow.fetchOne(db, key: consentRecordID) else { return nil }
        let participants =
            try ConsentRecordParticipantRow
            .filter(Column("consent_record_id") == consentRecordID)
            .order(Column("position"))
            .fetchAll(db)
            .map { PersonID(rawValue: UUID(uuidString: $0.personID) ?? UUID()) }
        return try row.asDomain(participantsAcknowledged: participants)
    }

    private static func syncParticipants(_ db: Database, consentRecordID: String, record: ConsentRecord) throws {
        try db.execute(
            sql: "DELETE FROM consent_record_participant WHERE consent_record_id = ?", arguments: [consentRecordID])
        for (position, personID) in record.participantsAcknowledged.enumerated() {
            try ConsentRecordParticipantRow(
                consentRecordID: consentRecordID, personID: personID.rawValue.uuidString, position: position
            ).insert(db)
        }
    }
}
