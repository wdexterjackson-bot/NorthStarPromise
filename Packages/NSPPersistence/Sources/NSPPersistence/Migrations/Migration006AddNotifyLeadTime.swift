import GRDB

/// Adds `scheduled_recording.notify_lead_time` — how many seconds before
/// `scheduled_start` the reminder notification fires (docs/07 §2.1: "None
/// to 2 minutes and 30 seconds"). `NOT NULL DEFAULT 0` backfills every
/// existing row to "fires exactly at the start time," the only behavior
/// that existed before this column.
enum Migration006AddNotifyLeadTime: SchemaMigration {
    static let identifier = "006_addScheduledRecordingNotifyLeadTime"

    static func up(_ db: Database) throws {
        try db.alter(table: "scheduled_recording") { t in
            t.add(column: "notify_lead_time", .double).notNull().defaults(to: 0)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "scheduled_recording") { t in
            t.drop(column: "notify_lead_time")
        }
    }
}
