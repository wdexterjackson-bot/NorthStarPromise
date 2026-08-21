import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBNoteBlockRepository")
struct GRDBNoteBlockRepositoryTests {
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

    private static func makeBlock(
        meetingID: MeetingID, authorID: PersonID, type: NoteBlockType = .richText,
        content: BlockContent = .text("hello"), opLog: [NSPCore.Operation] = []
    ) -> NoteBlock {
        NoteBlock(
            blockID: NoteBlockID(rawValue: UUID()), owner: .meeting(meetingID), authorID: authorID, type: type,
            content: content, creationRange: SampleRange(startSample: 0, endSample: 1000), opLog: opLog)
    }

    @Test func test_insertThenFind_roundTripsAllFieldsIncludingDefaultPrivacy() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let block = Self.makeBlock(meetingID: meetingID, authorID: personID)

        try await repository.insert(block, at: Date(timeIntervalSince1970: 1_700_000_000))
        let found = try await repository.find(block.blockID)

        #expect(found == block)
        #expect(found?.privacy == .privateToAuthor)
    }

    @Test func test_insertThenFind_roundTripsAssetReferenceContent() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let block = Self.makeBlock(
            meetingID: meetingID, authorID: personID, type: .sketch,
            content: .assetReference(path: "ink/abc.drawing"))

        try await repository.insert(block, at: Date())
        let found = try await repository.find(block.blockID)

        #expect(found?.content == .assetReference(path: "ink/abc.drawing"))
    }

    @Test func test_insertThenFind_roundTripsTheOpLogInOrder() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let opLog = [
            Operation(authorID: personID, timestamp: 1, content: .text("first")),
            Operation(authorID: personID, timestamp: 2, content: .text("second")),
            Operation(authorID: personID, timestamp: 3, content: .text("third")),
        ]
        let block = Self.makeBlock(meetingID: meetingID, authorID: personID, opLog: opLog)

        try await repository.insert(block, at: Date())
        let found = try await repository.find(block.blockID)

        #expect(found?.opLog == opLog)
    }

    @Test func test_update_replacesTheOpLogRatherThanAccumulating() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        var block = Self.makeBlock(
            meetingID: meetingID, authorID: personID,
            opLog: [Operation(authorID: personID, timestamp: 1, content: .text("first"))])
        try await repository.insert(block, at: Date(timeIntervalSince1970: 1_700_000_000))

        block.opLog = [Operation(authorID: personID, timestamp: 2, content: .text("replaced"))]
        try await repository.update(block, at: Date(timeIntervalSince1970: 1_700_000_100))

        let found = try await repository.find(block.blockID)
        #expect(found?.opLog.count == 1)
        #expect(found?.opLog.first?.timestamp == 2)
    }

    @Test func test_update_missingRow_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let block = Self.makeBlock(meetingID: meetingID, authorID: personID)

        await #expect(throws: PersistenceError.self) { try await repository.update(block, at: Date()) }
    }

    @Test func test_fetchAll_returnsEveryBlockForTheMeeting() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let first = Self.makeBlock(meetingID: meetingID, authorID: personID)
        let second = Self.makeBlock(meetingID: meetingID, authorID: personID)
        try await repository.insert(first, at: Date())
        try await repository.insert(second, at: Date())

        let all = try await repository.fetchAll(owner: .meeting(meetingID))

        #expect(Set(all.map(\.blockID)) == Set([first.blockID, second.blockID]))
    }

    @Test func test_delete_removesTheBlockAndItsOpLog() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (meetingID, personID) = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        let block = Self.makeBlock(
            meetingID: meetingID, authorID: personID,
            opLog: [Operation(authorID: personID, timestamp: 1, content: .text("first"))])
        try await repository.insert(block, at: Date())

        try await repository.delete(block.blockID)

        let found = try await repository.find(block.blockID)
        #expect(found == nil)
    }
}
