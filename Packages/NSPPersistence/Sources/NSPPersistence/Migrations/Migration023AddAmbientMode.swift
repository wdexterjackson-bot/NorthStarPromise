import GRDB

/// Adds Ambient Mode's storage ("Overheard" recommendation, 2026-08-22,
/// NSP-161): the `ambient_suggestion` inbox table, `policy`'s three new
/// columns plus its `policy_ambient_trusted_location` child table (mirrors
/// `policy_blocked_location` exactly), `person.ambient_listening_opt_out`,
/// and `person.notes`'s sibling from the same pass gets no new column here
/// — only what this feature specifically needs.
enum Migration023AddAmbientMode: SchemaMigration {
    static let identifier = "023_addAmbientMode"

    static func up(_ db: Database) throws {
        try db.create(table: "ambient_suggestion") { t in
            t.column("ambient_suggestion_id", .text).primaryKey()
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("kind", .text).notNull()
            t.column("text", .text).notNull()
            t.column("thread_id", .text).references("thread", onDelete: .setNull)
            t.column("counterparty_id", .text).references("person", onDelete: .setNull)
            t.column("evidence_excerpt", .text).notNull()
            t.column("evidence_captured_at", .datetime).notNull()
            t.column("status", .text).notNull().defaults(to: "pending")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull()
        }

        try db.alter(table: "policy") { t in
            t.add(column: "ambient_mode_enabled", .boolean).notNull().defaults(to: false)
            t.add(column: "ambient_session_duration_minutes", .integer).notNull().defaults(to: 60)
        }
        try db.create(table: "policy_ambient_trusted_location") { t in
            t.column("policy_id", .text).notNull().references("policy", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("location", .text).notNull()
            t.primaryKey(["policy_id", "position"])
        }

        try db.alter(table: "person") { t in
            t.add(column: "ambient_listening_opt_out", .boolean).notNull().defaults(to: false)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "person") { t in
            t.drop(column: "ambient_listening_opt_out")
        }
        try db.drop(table: "policy_ambient_trusted_location")
        try db.alter(table: "policy") { t in
            t.drop(column: "ambient_mode_enabled")
            t.drop(column: "ambient_session_duration_minutes")
        }
        try db.drop(table: "ambient_suggestion")
    }
}
