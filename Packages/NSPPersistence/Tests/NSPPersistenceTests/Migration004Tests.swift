import Foundation
import GRDB
import Testing

@testable import NSPPersistence

@Suite("Migration004AddFTSTriggers")
struct Migration004Tests {
    private struct MeetingFixture {
        let meetingID: String
        let turnID: String
    }

    /// Inserts one workspace/policy/meeting/transcript_turn graph via raw
    /// SQL — same shape `GRDBActionRepositoryTests.makeMeetingGraph` already
    /// uses elsewhere in this suite, extended with the one extra row
    /// (`transcript_turn`) this migration's triggers actually act on.
    private static func makeMeetingWithTurn(_ db: Database, excludedFromMemory: Bool = false) throws -> MeetingFixture {
        let workspaceID = UUID().uuidString
        let policyID = UUID().uuidString
        let meetingID = UUID().uuidString
        let turnID = UUID().uuidString

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
                    '2026-01-01', 'ready', ?, 'localOnly', 'complete',
                    ?, '2026-01-01', '2026-01-01', 1
                )
                """, arguments: [meetingID, workspaceID, policyID, excludedFromMemory])
        try db.execute(
            sql: """
                INSERT INTO transcript_turn (
                    turn_id, meeting_id, revision, is_provisional, edit_state, created_at, updated_at, row_revision
                ) VALUES (?, ?, 1, 0, 'machine', '2026-01-01', '2026-01-01', 1)
                """, arguments: [turnID, meetingID])

        return MeetingFixture(meetingID: meetingID, turnID: turnID)
    }

    private static func insertToken(_ db: Database, turnID: String, position: Int, text: String) throws {
        try db.execute(
            sql: """
                INSERT INTO transcript_token (turn_id, position, text, start_sample, end_sample, confidence)
                VALUES (?, ?, ?, ?, ?, 0.9)
                """, arguments: [turnID, position, text, position * 100, position * 100 + 99])
    }

    @Test func test_insertingTokens_populatesFtsTranscriptWithConcatenatedBody() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db)
            try Self.insertToken(db, turnID: fixture.turnID, position: 0, text: "hello")
            try Self.insertToken(db, turnID: fixture.turnID, position: 1, text: "world")

            let body = try String.fetchOne(
                db, sql: "SELECT body FROM fts_transcript WHERE turn_id = ?", arguments: [fixture.turnID])
            #expect(body == "hello world")
        }
    }

    @Test func test_excludedFromMemoryMeeting_neverGetsIndexed() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db, excludedFromMemory: true)
            try Self.insertToken(db, turnID: fixture.turnID, position: 0, text: "secret")

            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM fts_transcript WHERE turn_id = ?", arguments: [fixture.turnID])
            #expect(count == 0)
        }
    }

    @Test func test_excludingAMeetingAfterIndexing_purgesItsFtsAndEmbeddingRows() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db)
            try Self.insertToken(db, turnID: fixture.turnID, position: 0, text: "hello")
            try db.execute(
                sql: """
                    INSERT INTO embedding (
                        embedding_id, meeting_id, model_identifier, vector, excluded_from_memory,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'test-model', X'0000', 0, '2026-01-01', '2026-01-01', 1)
                    """, arguments: [UUID().uuidString, fixture.meetingID])

            try db.execute(
                sql: "UPDATE meeting SET excluded_from_memory = 1 WHERE meeting_id = ?",
                arguments: [fixture.meetingID])

            let ftsCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM fts_transcript WHERE turn_id = ?", arguments: [fixture.turnID])
            #expect(ftsCount == 0)
            let embeddingExcluded = try Bool.fetchOne(
                db, sql: "SELECT excluded_from_memory FROM embedding WHERE meeting_id = ?",
                arguments: [fixture.meetingID])
            #expect(embeddingExcluded == true)
        }
    }

    @Test func test_deletingATurn_cascadesToRemoveItsFtsRow() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db)
            try Self.insertToken(db, turnID: fixture.turnID, position: 0, text: "hello")

            try db.execute(sql: "DELETE FROM transcript_turn WHERE turn_id = ?", arguments: [fixture.turnID])

            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM fts_transcript WHERE turn_id = ?", arguments: [fixture.turnID])
            #expect(count == 0)
        }
    }

    @Test func test_insertingATextNoteBlock_populatesFtsNotes() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db)
            let personID = UUID().uuidString
            try db.execute(
                sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, (SELECT workspace_id FROM meeting WHERE meeting_id = ?), 'Author', "
                    + "'2026-01-01', '2026-01-01', 1)", arguments: [personID, fixture.meetingID])
            let blockID = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO note_block (
                        block_id, meeting_id, author_id, type, content_kind, content_text,
                        creation_range_start_sample, creation_range_end_sample, privacy, merge_state,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, ?, 'general', 'text', 'remember the budget', 0, 100, 'shared', 'none',
                        '2026-01-01', '2026-01-01', 1)
                    """, arguments: [blockID, fixture.meetingID, personID])

            let body = try String.fetchOne(
                db, sql: "SELECT body FROM fts_notes WHERE block_id = ?", arguments: [blockID])
            #expect(body == "remember the budget")
        }
    }

    @Test func test_insertingAnInsight_populatesFtsInsight() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeMeetingWithTurn(db)
            let insightID = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO insight (
                        insight_id, meeting_id, layer, text, claim_kind, confidence,
                        provenance_model_id, provenance_model_version, provenance_prompt_version,
                        provenance_generated_at, provenance_processing_plane,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'executiveSummary', 'The team decided to ship Friday', 'aiSuggests', 0.6,
                        'test', '1', '1', '2026-01-01', 'onDevice', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [insightID, fixture.meetingID])

            let body = try String.fetchOne(
                db, sql: "SELECT body FROM fts_insight WHERE insight_id = ?", arguments: [insightID])
            #expect(body == "The team decided to ship Friday")
        }
    }
}
