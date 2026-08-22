import GRDB

/// Adds `thread_participant` and `project_person` — the people tracked
/// against a Thread or Project (People plan phase 2, 2026-08-22), same
/// two-column composite-key, cascade-delete shape as `meeting_attendee`
/// (`Migration001InitialSchema`) and `meeting_thread`
/// (`Migration015AddMeetingThreadBridge`).
enum Migration021AddThreadAndProjectPersonJoins: SchemaMigration {
    static let identifier = "021_addThreadAndProjectPersonJoins"

    static func up(_ db: Database) throws {
        try db.create(table: "thread_participant") { t in
            t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.primaryKey(["thread_id", "person_id"])
        }
        try db.create(table: "project_person") { t in
            t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.primaryKey(["project_id", "person_id"])
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "project_person")
        try db.drop(table: "thread_participant")
    }
}
