import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBConsentRecordRepository")
struct GRDBConsentRecordRepositoryTests {
    private static func makeMeetingGraph(_ appDatabase: AppDatabase) async throws -> (MeetingID, PersonID) {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
        let personID = PersonID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, 'Workspace', '2026-01-01', '2026-01-01', 1)",
                arguments: [workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """, arguments: [policyID.rawValue.uuidString, workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision)
                    VALUES (?, ?, 'Author', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Test meeting', 0, 'watch', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'ready', ?, 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """,
                arguments: [
                    meetingID.rawValue.uuidString, workspaceID.rawValue.uuidString, policyID.rawValue.uuidString,
                ])
        }
        return (meetingID, personID)
    }

    @Test func test_insertThenFind_roundTripsAllFieldsIncludingParticipants() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBConsentRecordRepository(dbWriter: appDatabase.dbWriter)

        let record = ConsentRecord(
            consentRecordID: ConsentRecordID(rawValue: UUID()), meetingID: meetingID, method: .checklistConfirmed,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), participantsAcknowledged: [personID])

        try await repository.insert(record, at: Date())
        let found = try await repository.find(record.consentRecordID)

        #expect(found == record)
    }

    @Test func test_hasRecord_isTrueOnlyAfterInsertForThatMeeting() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, _) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBConsentRecordRepository(dbWriter: appDatabase.dbWriter)

        #expect(try await repository.hasRecord(forMeetingID: meetingID) == false)

        let record = ConsentRecord(
            consentRecordID: ConsentRecordID(rawValue: UUID()), meetingID: meetingID, method: .verbalAnnouncement,
            timestamp: Date())
        try await repository.insert(record, at: Date())

        #expect(try await repository.hasRecord(forMeetingID: meetingID) == true)
    }

    @Test func test_find_missingRecord_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBConsentRecordRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(ConsentRecordID(rawValue: UUID())) == nil)
    }
}
