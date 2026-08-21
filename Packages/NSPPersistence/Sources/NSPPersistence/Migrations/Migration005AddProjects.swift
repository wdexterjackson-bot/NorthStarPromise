import GRDB

/// Adds `project` (a named grouping of meetings/notes) and the
/// `meeting_project` join table — many-to-many rather than a single
/// `project_id` column on `meeting`, since a mental note
/// (`RecordingIntent.mentalNote`) can carry action items relevant to
/// several projects at once, while a regular meeting typically joins just
/// one (`Project`'s own doc comment). Also adds `meeting.recording_intent`
/// — `NOT NULL DEFAULT 'meeting'` so every existing row backfills to the
/// only intent that existed before this migration.
enum Migration005AddProjects: SchemaMigration {
    static let identifier = "005_addProjects"

    static func up(_ db: Database) throws {
        try db.create(table: "project") { t in
            t.primaryKey("project_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("archived_at", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        try db.create(table: "meeting_project") { t in
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
            t.primaryKey(["meeting_id", "project_id"])
        }

        try db.alter(table: "meeting") { t in
            t.add(column: "recording_intent", .text).notNull().defaults(to: "meeting")
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "meeting_project")
        try db.drop(table: "project")
        try db.alter(table: "meeting") { t in
            t.drop(column: "recording_intent")
        }
    }
}
