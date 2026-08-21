import Foundation
import GRDB
import Testing

@testable import NSPPersistence

@Suite("Migration014ConvertMentalNoteMeetings")
struct Migration014Tests {
    private struct Fixture {
        let mentalNoteMeetingID: String
        var ordinaryMeetingID: String
        let segmentID: String
        let turnID: String
        let blockID: String
        let eventID: String
    }

    /// One `mentalNote`-flavored meeting (with a segment/transcript turn/
    /// note block/timeline event already pointing at it, `owner_kind =
    /// 'meeting'`) plus one ordinary `.meeting`-flavored meeting, to prove
    /// the migration only ever touches the former.
    private static func makeFixture(_ db: Database) throws -> Fixture {
        let workspaceID = UUID().uuidString
        let policyID = UUID().uuidString
        let deviceID = "AAAAAAAA-0000-7000-8000-000000000001"
        let mentalNoteMeetingID = UUID().uuidString
        let ordinaryMeetingID = UUID().uuidString

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
        for (meetingID, intent) in [(mentalNoteMeetingID, "mentalNote"), (ordinaryMeetingID, "meeting")] {
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision, recording_intent
                    ) VALUES (
                        ?, ?, 'Test meeting', 0, 'phone', ?,
                        '2026-01-01', 'savedRaw', ?, 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1, ?
                    )
                    """, arguments: [meetingID, workspaceID, deviceID, policyID, intent])
        }

        var fixture = try makeOwnedRows(
            db, workspaceID: workspaceID, deviceID: deviceID, meetingID: mentalNoteMeetingID)
        fixture.ordinaryMeetingID = ordinaryMeetingID
        return fixture
    }

    /// The one segment/transcript turn/note block/timeline event this suite
    /// checks all flip `owner_kind` together — split out of `makeFixture`
    /// purely to stay under this repo's 50-line function-body budget.
    /// `ordinaryMeetingID` is a placeholder here — `makeFixture` fills in
    /// the real value once this returns.
    private static func makeOwnedRows(
        _ db: Database, workspaceID: String, deviceID: String, meetingID: String
    ) throws -> Fixture {
        let segmentID = UUID().uuidString
        try db.execute(
            sql: """
                INSERT INTO segment (
                    segment_id, meeting_id, owner_kind, device_id, sequence, codec, sample_rate, channels,
                    bit_rate, start_sample, sample_count, transfer_state, is_repaired_tail,
                    created_at, updated_at, row_revision
                ) VALUES (?, ?, 'meeting', ?, 0, 'aacLC', 16000, 1, 32000, 0, 1000, 'local', 0,
                    '2026-01-01', '2026-01-01', 1)
                """, arguments: [segmentID, meetingID, deviceID])

        let turnID = UUID().uuidString
        try db.execute(
            sql: """
                INSERT INTO transcript_turn (
                    turn_id, meeting_id, owner_kind, revision, is_provisional, edit_state,
                    created_at, updated_at, row_revision
                ) VALUES (?, ?, 'meeting', 1, 0, 'machine', '2026-01-01', '2026-01-01', 1)
                """, arguments: [turnID, meetingID])

        let personID = UUID().uuidString
        try db.execute(
            sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                + "VALUES (?, ?, 'Author', '2026-01-01', '2026-01-01', 1)", arguments: [personID, workspaceID])
        let blockID = UUID().uuidString
        try db.execute(
            sql: """
                INSERT INTO note_block (
                    block_id, meeting_id, owner_kind, author_id, type, content_kind, content_text,
                    creation_range_start_sample, creation_range_end_sample, privacy, merge_state,
                    created_at, updated_at, row_revision
                ) VALUES (?, ?, 'meeting', ?, 'general', 'text', 'stream of consciousness', 0, 100,
                    'privateToAuthor', 'standalone', '2026-01-01', '2026-01-01', 1)
                """, arguments: [blockID, meetingID, personID])

        let eventID = UUID().uuidString
        try db.execute(
            sql: """
                INSERT INTO timeline_event (
                    event_id, meeting_id, owner_kind, device_id, type, sample_offset, wall_clock,
                    created_at, updated_at, row_revision
                ) VALUES (?, ?, 'meeting', ?, 'start', 0, '2026-01-01', '2026-01-01', '2026-01-01', 1)
                """, arguments: [eventID, meetingID, deviceID])

        return Fixture(
            mentalNoteMeetingID: meetingID, ordinaryMeetingID: "", segmentID: segmentID, turnID: turnID,
            blockID: blockID, eventID: eventID)
    }

    /// `Migration014ConvertMentalNoteMeetings` already ran (as a no-op) by
    /// the time `AppDatabase.makeInMemory()` returns, since that's before
    /// any fixture data exists — so every test here inserts fixture rows
    /// into the already-migrated schema and then calls `up(_:)` directly,
    /// exactly as `DatabaseMigrator` would have if this data had existed
    /// at migration time.
    private static func makeFixtureAndRunMigration(_ appDatabase: AppDatabase) throws -> Fixture {
        try appDatabase.dbWriter.write { db in
            let fixture = try Self.makeFixture(db)
            try Migration014ConvertMentalNoteMeetings.up(db)
            return fixture
        }
    }

    @Test func test_mentalNoteMeeting_becomesABrainDumpWithTheSameID() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try Self.makeFixtureAndRunMigration(appDatabase)

        let brainDumpCount = try appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM brain_dump WHERE brain_dump_id = ?",
                arguments: [fixture.mentalNoteMeetingID])
        }
        #expect(brainDumpCount == 1)

        let meetingStillExists = try appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meeting WHERE meeting_id = ?",
                arguments: [fixture.mentalNoteMeetingID])
        }
        #expect(meetingStillExists == 0)
    }

    @Test func test_mentalNoteMeeting_ownedRowsFlipToBrainDumpOwnerKind() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try Self.makeFixtureAndRunMigration(appDatabase)

        try appDatabase.dbWriter.read { db in
            for (table, column, id) in [
                ("segment", "segment_id", fixture.segmentID), ("transcript_turn", "turn_id", fixture.turnID),
                ("note_block", "block_id", fixture.blockID), ("timeline_event", "event_id", fixture.eventID),
            ] {
                let ownerKind = try String.fetchOne(
                    db, sql: "SELECT owner_kind FROM \(table) WHERE \(column) = ?", arguments: [id])
                #expect(ownerKind == "brainDump", "\(table) didn't flip to brainDump")
            }
        }
    }

    @Test func test_ordinaryMeeting_isUntouched() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try Self.makeFixtureAndRunMigration(appDatabase)

        let stillAMeeting = try appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meeting WHERE meeting_id = ?", arguments: [fixture.ordinaryMeetingID])
        }
        #expect(stillAMeeting == 1)
        let neverABrainDump = try appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM brain_dump WHERE brain_dump_id = ?",
                arguments: [fixture.ordinaryMeetingID])
        }
        #expect(neverABrainDump == 0)
    }
}
