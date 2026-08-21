import Foundation
import GRDB
import Testing

@testable import NSPPersistence

/// Regression coverage for the exact scenario `AppDatabase.makeInMemory()`
/// can't exercise on its own: a database that already has real `meeting`/
/// `action_item` rows (with a `meeting.thread_id` set) from *before*
/// `Migration015AddMeetingThreadBridge`/`Migration016AddFreestandingActions`
/// existed, then upgrades. Every other test in this suite inserts its
/// fixture data *after* `makeInMemory()` has already run every migration,
/// which never exercises what these two migrations do to pre-existing rows.
@Suite("Migration015/016 — upgrading a database with real pre-existing data")
struct Migration015And016UpgradeTests {
    /// Migrates only through `Migration014ConvertMentalNoteMeetings` —
    /// `Migration015`/`016` are applied explicitly afterward, once real
    /// fixture data already exists, mirroring what an actual app upgrade
    /// looks like.
    private static func makeDatabaseThroughMigration014() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        var migrator = DatabaseMigrator()
        for migration in AppDatabase.allMigrations {
            if migration.identifier == Migration015AddMeetingThreadBridge.identifier { break }
            migrator.registerMigration(migration.identifier) { db in try migration.up(db) }
        }
        try migrator.migrate(dbQueue)
        return dbQueue
    }

    private struct PreExistingFixture {
        let workspaceID: String
        let policyID: String
        let personID: String
        let meetingID: String
        let threadID: String
        let actionID: String
    }

    /// Inserts one workspace/policy/person/thread/meeting/action graph
    /// directly, pre-`Migration015`/`016` shape — split out of the test
    /// itself purely to stay under this repo's 50-line function-body budget.
    private static func insertPreExistingGraph(_ dbQueue: DatabaseQueue) throws -> PreExistingFixture {
        let workspaceID = UUID().uuidString
        let policyID = UUID().uuidString
        let personID = UUID().uuidString
        let meetingID = UUID().uuidString
        let threadID = UUID().uuidString
        let actionID = UUID().uuidString

        try dbQueue.write { db in
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
                sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, ?, 'You', '2026-01-01', '2026-01-01', 1)", arguments: [personID, workspaceID])
            try db.execute(
                sql: """
                    INSERT INTO thread (
                        thread_id, workspace_id, title, kind, color_slot, status, last_touched_at,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'Vendor contract', 'initiative', 0, 'onTrack', '2026-01-01',
                        '2026-01-01', '2026-01-01', 1)
                    """, arguments: [threadID, workspaceID])
        }
        let fixture = PreExistingFixture(
            workspaceID: workspaceID, policyID: policyID, personID: personID, meetingID: meetingID,
            threadID: threadID, actionID: actionID)
        try Self.insertMeetingAndAction(dbQueue, fixture)
        return fixture
    }

    private static func insertMeetingAndAction(_ dbQueue: DatabaseQueue, _ fixture: PreExistingFixture) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision, recording_intent, thread_id
                    ) VALUES (
                        ?, ?, 'Weekly product sync', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'savedRaw', ?, 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1, 'meeting', ?
                    )
                    """,
                arguments: [fixture.meetingID, fixture.workspaceID, fixture.policyID, fixture.threadID])
            try db.execute(
                sql: """
                    INSERT INTO action_item (
                        action_id, meeting_id, text, owner_state, date_state, status, created_by,
                        created_at, updated_at, row_revision, direction, defer_count, asked_again_count,
                        confidence, edited
                    ) VALUES (?, ?, 'Send the recap', 'unresolved', 'unresolved', 'proposed', ?,
                        '2026-01-01', '2026-01-01', 1, 'iOwe', 0, 0, 1.0, 0)
                    """, arguments: [fixture.actionID, fixture.meetingID, fixture.personID])
        }
    }

    @Test func test_preExistingMeetingWithAThread_survivesBothMigrationsIntact() throws {
        let dbQueue = try Self.makeDatabaseThroughMigration014()
        let fixture = try Self.insertPreExistingGraph(dbQueue)
        let workspaceID = fixture.workspaceID
        let meetingID = fixture.meetingID
        let threadID = fixture.threadID
        let actionID = fixture.actionID

        try dbQueue.write { db in
            try Migration015AddMeetingThreadBridge.up(db)
            try Migration016AddFreestandingActions.up(db)
        }

        try dbQueue.read { db in
            let meetingCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meeting WHERE meeting_id = ?", arguments: [meetingID])
            #expect(meetingCount == 1, "the pre-existing meeting must survive both migrations")

            let actionCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM action_item WHERE action_id = ?", arguments: [actionID])
            #expect(actionCount == 1, "the pre-existing action must survive the action_item rebuild")

            let actionWorkspaceID = try String.fetchOne(
                db, sql: "SELECT workspace_id FROM action_item WHERE action_id = ?", arguments: [actionID])
            #expect(actionWorkspaceID == workspaceID, "workspace_id must be backfilled from the meeting's own")

            let bridgeCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meeting_thread WHERE meeting_id = ? AND thread_id = ?",
                arguments: [meetingID, threadID])
            #expect(bridgeCount == 1, "the pre-existing meeting.thread_id link must migrate into meeting_thread")
        }
    }
}
