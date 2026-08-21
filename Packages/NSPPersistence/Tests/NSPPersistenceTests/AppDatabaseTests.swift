import Foundation
import GRDB
import Testing

@testable import NSPPersistence

@Suite("AppDatabase")
struct AppDatabaseTests {
    @Test func test_makeInMemory_appliesAllMigrationsWithoutThrowing() throws {
        _ = try AppDatabase.makeInMemory()
    }

    /// `action_item`, not `segment`, is the table this proves FK enforcement
    /// against — `segment`/`transcript_turn`/`note_block` deliberately lost
    /// their `meeting_id` foreign key in `Migration012AddNotesAndBrainDumps`
    /// (a single column can't conditionally reference `meeting`/
    /// `brain_dump`/`note`; `OwnedContentCleanup` enforces that integrity at
    /// the app layer instead now). `action_item` still has a real FK to
    /// `meeting`, so it's still the right table to prove
    /// `configuration.foreignKeysEnabled` is actually on.
    @Test func test_foreignKeysAreEnabled_rejectsAnOrphanRow() throws {
        let appDatabase = try AppDatabase.makeInMemory()

        #expect(throws: DatabaseError.self) {
            try appDatabase.dbWriter.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO action_item (
                            action_id, meeting_id, text, created_by, created_at, updated_at
                        ) VALUES (
                            'action-1', 'no-such-meeting', 'Follow up', 'no-such-person',
                            '2026-01-01', '2026-01-01'
                        )
                        """)
            }
        }
    }

    @Test func test_walJournalModeIsConfiguredForFileBackedDatabases() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("nsp-test-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let appDatabase = try AppDatabase(path: path)
        let mode = try appDatabase.dbWriter.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "wal")
    }
}
