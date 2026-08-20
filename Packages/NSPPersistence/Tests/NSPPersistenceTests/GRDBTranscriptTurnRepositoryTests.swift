import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBTranscriptTurnRepository")
struct GRDBTranscriptTurnRepositoryTests {
    private struct MeetingGraph {
        let meetingID: MeetingID
        let segmentID: SegmentID
    }

    private static func makeMeetingGraph(_ appDatabase: AppDatabase) async throws -> MeetingGraph {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
        let segmentID = SegmentID(rawValue: UUID())
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
            try db.execute(
                sql: """
                    INSERT INTO segment (
                        segment_id, meeting_id, device_id, sequence, codec, sample_rate, channels, bit_rate,
                        start_sample, sample_count, sha256, local_url, transfer_state,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'AAAAAAAA-0000-7000-8000-000000000001', 0, 'aac-lc', 48000, 1, 64000,
                        0, 48000, 'deadbeef', '/tmp/segments/000000.m4a', 'local',
                        '2026-01-01', '2026-01-01', 1)
                    """, arguments: [segmentID.rawValue.uuidString, meetingID.rawValue.uuidString])
        }
        return MeetingGraph(meetingID: meetingID, segmentID: segmentID)
    }

    private static func makeTurn(meetingID: MeetingID, segmentID: SegmentID, startSample: Int64) -> TranscriptTurn {
        TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), meetingID: meetingID, revision: 1, isProvisional: false,
            tokens: [
                Token(text: "Hello", startSample: startSample, endSample: startSample + 100, confidence: 0.95),
                Token(text: "world", startSample: startSample + 100, endSample: startSample + 200, confidence: 0.9),
            ],
            languageSpans: [
                LanguageSpan(
                    languageTag: "en", range: SampleRange(startSample: startSample, endSample: startSample + 200))
            ],
            segmentRefs: [segmentID])
    }

    @Test func test_insertThenFind_roundTripsTokensAndLanguageSpansAndSegmentRefs() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBTranscriptTurnRepository(dbWriter: appDatabase.dbWriter)

        let turn = Self.makeTurn(meetingID: graph.meetingID, segmentID: graph.segmentID, startSample: 0)
        try await repository.insert(turn, at: Date())
        let found = try await repository.find(turn.turnID)

        #expect(found == turn)
    }

    @Test func test_fetchAll_ordersByFirstTokenStartSample() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBTranscriptTurnRepository(dbWriter: appDatabase.dbWriter)

        let later = Self.makeTurn(meetingID: graph.meetingID, segmentID: graph.segmentID, startSample: 5000)
        let earlier = Self.makeTurn(meetingID: graph.meetingID, segmentID: graph.segmentID, startSample: 100)
        try await repository.insert(later, at: Date())
        try await repository.insert(earlier, at: Date())

        let all = try await repository.fetchAll(meetingID: graph.meetingID)
        #expect(all.map(\.turnID) == [earlier.turnID, later.turnID])
    }

    @Test func test_update_replacesTokensRatherThanAccumulating() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBTranscriptTurnRepository(dbWriter: appDatabase.dbWriter)

        var turn = Self.makeTurn(meetingID: graph.meetingID, segmentID: graph.segmentID, startSample: 0)
        try await repository.insert(turn, at: Date())

        turn = TranscriptTurn(
            turnID: turn.turnID, meetingID: turn.meetingID, revision: turn.revision, isProvisional: false,
            tokens: [Token(text: "Hi", startSample: 0, endSample: 50, confidence: 1.0)], segmentRefs: turn.segmentRefs)
        try await repository.update(turn, at: Date())

        let found = try await repository.find(turn.turnID)
        #expect(found?.tokens.count == 1)
        #expect(found?.tokens.first?.text == "Hi")
    }

    @Test func test_find_missingTurn_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBTranscriptTurnRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(TranscriptTurnID(rawValue: UUID())) == nil)
    }
}
