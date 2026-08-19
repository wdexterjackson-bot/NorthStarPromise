import GRDB

/// A schema migration with both directions defined, so "reversible" (NSP-011
/// acceptance) is a property of the migration itself rather than a claim in a
/// comment. Forward application goes through GRDB's `DatabaseMigrator`, which
/// tracks what has already run; `down` has no equivalent built-in tracking in
/// GRDB, so it is invoked directly — by tests proving reversibility, and by
/// any future rollback tooling.
///
/// Migrations are numbered, append-only, and reversible (docs/02 §1, §5;
/// docs/11 §8): once shipped, a migration file is never edited — a change
/// ships as a new migration.
public protocol SchemaMigration {
    /// Matches the identifier `DatabaseMigrator.registerMigration` uses to
    /// track whether this migration has already run.
    static var identifier: String { get }

    static func up(_ db: Database) throws
    static func down(_ db: Database) throws
}
