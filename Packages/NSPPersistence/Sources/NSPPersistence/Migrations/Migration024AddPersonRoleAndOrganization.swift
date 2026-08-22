import GRDB

/// Adds `person.role` and `person.organization` — "The First Hour" wizard
/// (2026-08-22) asks for both on the self-Person in its identity step, but
/// they're general fields any Person can carry. Plain scalars, same
/// reasoning `Migration020AddPersonNotes` already used for `notes`.
enum Migration024AddPersonRoleAndOrganization: SchemaMigration {
    static let identifier = "024_addPersonRoleAndOrganization"

    static func up(_ db: Database) throws {
        try db.alter(table: "person") { t in
            t.add(column: "role", .text)
            t.add(column: "organization", .text)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "person") { t in
            t.drop(column: "role")
            t.drop(column: "organization")
        }
    }
}
