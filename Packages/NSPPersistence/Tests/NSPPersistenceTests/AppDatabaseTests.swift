import Foundation
import GRDB
import Testing

@testable import NSPPersistence

@Suite("AppDatabase")
struct AppDatabaseTests {
    @Test func test_makeInMemory_appliesAllMigrationsWithoutThrowing() throws {
        _ = try AppDatabase.makeInMemory()
    }

    @Test func test_foreignKeysAreEnabled_rejectsAnOrphanRow() throws {
        let appDatabase = try AppDatabase.makeInMemory()

        #expect(throws: DatabaseError.self) {
            try appDatabase.dbWriter.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO segment (
                            segment_id, meeting_id, device_id, sequence, codec, sample_rate,
                            channels, bit_rate, start_sample, sample_count, transfer_state,
                            is_repaired_tail, created_at, updated_at, row_revision
                        ) VALUES (
                            'seg-1', 'no-such-meeting', 'watch-1', 0, 'aac-lc', 16000,
                            1, 32000, 0, 100, 'local',
                            0, '2026-01-01', '2026-01-01', 1
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
