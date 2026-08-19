import Foundation
import GRDB

/// Opens and configures the GRDB connection: foreign keys enforced, WAL
/// journal mode, every registered migration applied (docs/01 §2, docs/02 §5).
/// This is `NSPPersistence`'s single entry point for a database handle —
/// repositories (NSP-012) depend on this, never on GRDB directly at the call
/// site, so tests can swap in `makeInMemory()`.
public struct AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    /// docs/02 §5: "Foreign keys on, WAL mode on, synchronous = FULL on the
    /// capture device during an active recording." `synchronous` is left at
    /// GRDB's default (`FULL`) here; raising it further during active
    /// capture is `NSPMedia`'s job (docs/03 §2), out of this ticket's scope.
    public static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        return configuration
    }

    /// All migrations, in order. Adding a new one means appending here and
    /// creating a new file — never editing a migration already shipped
    /// (docs/02 §1, docs/11 §8).
    ///
    /// `nonisolated(unsafe)`: an array of metatypes is immutable compile-time
    /// data, not shared mutable state — Swift 6 flags `any P.Type` arrays
    /// regardless. NSP-011.
    nonisolated(unsafe) static let allMigrations: [SchemaMigration.Type] = [
        Migration001InitialSchema.self
    ]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for migration in allMigrations {
            migrator.registerMigration(migration.identifier) { db in
                try migration.up(db)
            }
        }
        return migrator
    }

    /// Opens (creating if needed) the database file at `path` and brings it
    /// up to the latest schema.
    public init(path: String) throws {
        let dbQueue = try DatabaseQueue(path: path, configuration: Self.makeConfiguration())
        try Self.migrator.migrate(dbQueue)
        self.dbWriter = dbQueue
    }

    /// An in-memory store for tests (NSP-011 acceptance: "in-memory store
    /// available for tests") — same schema, same migration path, zero disk
    /// I/O, so tests never share state across runs.
    public static func makeInMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: makeConfiguration())
        try migrator.migrate(dbQueue)
        return AppDatabase(dbWriter: dbQueue)
    }

    private init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }
}
