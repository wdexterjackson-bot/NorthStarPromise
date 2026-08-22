import GRDB

/// Adds `person.notes` — freeform context the user writes about a person
/// directly (People plan phase 2, 2026-08-22). A plain scalar, unlike
/// `tags`/`aliases`, so it's a direct column rather than a sibling table.
enum Migration020AddPersonNotes: SchemaMigration {
    static let identifier = "020_addPersonNotes"

    static func up(_ db: Database) throws {
        try db.alter(table: "person") { t in
            t.add(column: "notes", .text)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "person") { t in
            t.drop(column: "notes")
        }
    }
}
