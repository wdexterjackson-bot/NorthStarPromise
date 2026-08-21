import GRDB

/// Adds `scheduled_recording` (docs/07 §2.1) — a pre-scheduled recording,
/// manual or calendar-imported, with a mandatory Start/Skip notification
/// and unattended auto-stop. Deliberately no `cloud_record_change_tag`:
/// `NSPSync` isn't wired to this table, so it stays local-only bookkeeping
/// in v1 (a follow-up ticket can add sync if wanted).
enum Migration003AddScheduledRecording: SchemaMigration {
    static let identifier = "003_addScheduledRecording"

    static func up(_ db: Database) throws {
        try db.create(table: "scheduled_recording") { t in
            t.primaryKey("scheduled_recording_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("scheduled_start", .datetime).notNull()
            t.column("scheduled_stop", .datetime).notNull()
            t.column("status", .text).notNull().defaults(to: "pending")
            t.column("alert_style", .text).notNull().defaults(to: "sound")
            t.column("calendar_event_id", .text)
            t.column("meeting_id", .text).references("meeting", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "scheduled_recording")
    }
}
