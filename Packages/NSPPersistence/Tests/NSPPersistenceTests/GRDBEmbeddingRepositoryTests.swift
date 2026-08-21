import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBEmbeddingRepository")
struct GRDBEmbeddingRepositoryTests {
    private static func makeMeeting(_ appDatabase: AppDatabase) async throws -> MeetingID {
        let workspaceID = UUID().uuidString
        let policyID = UUID().uuidString
        let meetingID = MeetingID(rawValue: UUID())
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
        }
        return meetingID
    }

    private static func chunk(_ vector: [Float], text: String = "hello world") -> EmbeddingChunkInput {
        EmbeddingChunkInput(
            turnIDs: [TranscriptTurnID(rawValue: UUID())], sampleStart: 0, sampleEnd: 100, text: text, vector: vector)
    }

    @Test func test_replaceAllThenFetchCandidates_roundTripsTheVectorExactly() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)
        let vector: [Float] = [0.5, -0.25, 0.0, 1.0, -1.0, 3.14159]

        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk(vector)], modelIdentifier: "test-model", at: Date())
        let candidates = try await repository.fetchCandidates(meetingIDs: [meetingID], modelIdentifier: "test-model")

        #expect(candidates.count == 1)
        #expect(candidates.first?.vector == vector)
        #expect(candidates.first?.chunkText == "hello world")
    }

    @Test func test_replaceAll_isAFullReplaceNotAnAccumulation() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)

        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk([1, 2, 3]), Self.chunk([4, 5, 6])],
            modelIdentifier: "test-model", at: Date())
        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk([7, 8, 9])], modelIdentifier: "test-model", at: Date())

        let candidates = try await repository.fetchCandidates(meetingIDs: [meetingID], modelIdentifier: "test-model")
        #expect(candidates.count == 1)
        #expect(candidates.first?.vector == [7, 8, 9])
    }

    @Test func test_fetchCandidates_excludesOtherModelIdentifiers() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)

        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk([1, 2, 3])], modelIdentifier: "old-model", at: Date())

        let candidates = try await repository.fetchCandidates(meetingIDs: [meetingID], modelIdentifier: "new-model")
        #expect(candidates.isEmpty)
    }

    @Test func test_fetchCandidates_excludesRowsMarkedExcludedFromMemory() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)
        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk([1, 2, 3])], modelIdentifier: "test-model", at: Date())

        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE embedding SET excluded_from_memory = 1 WHERE meeting_id = ?",
                arguments: [meetingID.rawValue.uuidString])
        }

        let candidates = try await repository.fetchCandidates(meetingIDs: [meetingID], modelIdentifier: "test-model")
        #expect(candidates.isEmpty)
    }

    @Test func test_fetchCandidates_emptyMeetingSet_returnsEmptyWithoutQuerying() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)
        let candidates = try await repository.fetchCandidates(meetingIDs: [], modelIdentifier: "test-model")
        #expect(candidates.isEmpty)
    }

    @Test func test_delete_removesAllChunksForTheMeeting() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter)
        try await repository.replaceAll(
            meetingID: meetingID, chunks: [Self.chunk([1, 2, 3])], modelIdentifier: "test-model", at: Date())

        try await repository.delete(meetingID: meetingID)

        let candidates = try await repository.fetchCandidates(meetingIDs: [meetingID], modelIdentifier: "test-model")
        #expect(candidates.isEmpty)
    }
}
