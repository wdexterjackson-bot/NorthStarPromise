import GRDB

/// Adds `person_tag` — one row per `Person.tags` entry, ordered by
/// `position`. Same shape as the existing `person_alias` table (`Migration001
/// InitialSchema`): freeform relationship labels ("Direct report", "Board",
/// "Vendor") the People recommendation (2026-08-22) calls for, deliberately
/// not an enum since an executive's roster doesn't fit one fixed taxonomy.
enum Migration018AddPersonTags: SchemaMigration {
    static let identifier = "018_addPersonTags"

    static func up(_ db: Database) throws {
        try db.create(table: "person_tag") { t in
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("tag", .text).notNull()
            t.primaryKey(["person_id", "position"])
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "person_tag")
    }
}
