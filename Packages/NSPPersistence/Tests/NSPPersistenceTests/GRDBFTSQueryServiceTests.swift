import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBFTSQueryService")
struct GRDBFTSQueryServiceTests {
    private static func makeMeetingWithTurn(_ appDatabase: AppDatabase, body: String) async throws -> MeetingID {
        let workspaceID = UUID().uuidString
        let policyID = UUID().uuidString
        let meetingID = MeetingID(rawValue: UUID())
        let turnID = UUID().uuidString
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, 'Workspace', '2026-01-01', '2026-01-01', 1)", arguments: [workspaceID])
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """, arguments: [policyID, workspaceID])
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Test meeting', 0, 'watch', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'ready', ?, 'localOnly', 'complete', 0, '2026-01-01', '2026-01-01', 1
                    )
                    """, arguments: [meetingID.rawValue.uuidString, workspaceID, policyID])
            try db.execute(
                sql: """
                    INSERT INTO transcript_turn (
                        turn_id, meeting_id, revision, is_provisional, edit_state, created_at, updated_at, row_revision
                    ) VALUES (?, ?, 1, 0, 'machine', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [turnID, meetingID.rawValue.uuidString])
            for (index, word) in body.components(separatedBy: " ").enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO transcript_token (turn_id, position, text, start_sample, end_sample, confidence)
                        VALUES (?, ?, ?, ?, ?, 0.9)
                        """, arguments: [turnID, index, word, index * 100, index * 100 + 99])
            }
        }
        return meetingID
    }

    @Test func test_search_findsAMeaningfulTermButIgnoresStopwords() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeetingWithTurn(
            appDatabase, body: "the executive report is due friday")
        let service = GRDBFTSQueryService(dbWriter: appDatabase.dbWriter)

        // "when" and "is" never appeared in the transcript at all — if the
        // stopword filter didn't work, a raw MATCH on the literal question
        // would still need to not blow up on a term that isn't in the
        // corpus; the real proof is that "executive"/"report"/"due" (the
        // actual content words) are what drive the hit.
        let hits = try await service.search(
            query: "when is the executive report due", meetingIDs: [meetingID], limit: 10)

        #expect(hits.contains { $0.source == .transcript && $0.meetingID == meetingID })
    }

    @Test func test_search_unscopedMeetingID_neverReturnsAHit() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        _ = try await Self.makeMeetingWithTurn(appDatabase, body: "the executive report is due friday")
        let service = GRDBFTSQueryService(dbWriter: appDatabase.dbWriter)

        // A real meeting exists and matches the query, but the caller only
        // authorizes a different, unrelated meeting ID.
        let unrelatedMeetingID = MeetingID(rawValue: UUID())
        let hits = try await service.search(query: "executive report", meetingIDs: [unrelatedMeetingID], limit: 10)

        #expect(hits.isEmpty)
    }

    @Test func test_search_onlyStopwords_returnsEmptyWithoutQuerying() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeetingWithTurn(appDatabase, body: "the executive report is due friday")
        let service = GRDBFTSQueryService(dbWriter: appDatabase.dbWriter)

        let hits = try await service.search(query: "when is the", meetingIDs: [meetingID], limit: 10)

        #expect(hits.isEmpty)
    }

    @Test func test_search_punctuationInQuery_doesNotThrow() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeetingWithTurn(appDatabase, body: "the executive report is due friday")
        let service = GRDBFTSQueryService(dbWriter: appDatabase.dbWriter)

        let hits = try await service.search(
            query: "when's the \"Executive Report\" due?!", meetingIDs: [meetingID], limit: 10)

        #expect(hits.contains { $0.meetingID == meetingID })
    }
}
