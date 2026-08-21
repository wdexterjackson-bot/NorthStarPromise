import GRDB

/// Adds the join table that turns `Person` from "just you" into real
/// meeting attendees (`meeting_attendee`), and the `thread_in_motion`
/// entity plus its two join tables — `thread_meeting` (meetings linked
/// directly) and `thread_project` (whole projects linked, meaning every
/// meeting under that project is transitively part of the thread too).
enum Migration007AddPeopleAndThreads: SchemaMigration {
    static let identifier = "007_addPeopleAndThreads"

    static func up(_ db: Database) throws {
        try db.create(table: "meeting_attendee") { t in
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.primaryKey(["meeting_id", "person_id"])
        }

        try db.create(table: "thread_in_motion") { t in
            t.primaryKey("thread_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        try db.create(table: "thread_meeting") { t in
            t.column("thread_id", .text).notNull().references("thread_in_motion", onDelete: .cascade)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.primaryKey(["thread_id", "meeting_id"])
        }

        try db.create(table: "thread_project") { t in
            t.column("thread_id", .text).notNull().references("thread_in_motion", onDelete: .cascade)
            t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
            t.primaryKey(["thread_id", "project_id"])
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "thread_project")
        try db.drop(table: "thread_meeting")
        try db.drop(table: "thread_in_motion")
        try db.drop(table: "meeting_attendee")
    }
}
