import GRDB

/// Adds `scheduled_recording.project_id` — a project chosen at scheduling
/// time, applied to the resulting `Meeting` the moment it's created
/// (`ScheduledRecording.projectID`'s own doc comment).
enum Migration008AddScheduledRecordingProject: SchemaMigration {
    static let identifier = "008_addScheduledRecordingProject"

    static func up(_ db: Database) throws {
        try db.alter(table: "scheduled_recording") { t in
            t.add(column: "project_id", .text).references("project", onDelete: .setNull)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "scheduled_recording") { t in
            t.drop(column: "project_id")
        }
    }
}
