import GRDB

/// Adds `recurrence_rule` and `recurrence_exception` (NSP-157) plus the
/// optional `meeting.recurrence_rule_id`/`scheduled_recording
/// .recurrence_rule_id` columns that point a promoted occurrence back at
/// its series. `RecurrenceExpander` never materializes future occurrences
/// as rows — only a started/edited occurrence gets one of these columns
/// set, exactly like the rule-plus-exceptions model every real calendar
/// app uses.
enum Migration019AddRecurrence: SchemaMigration {
    static let identifier = "019_addRecurrence"

    static func up(_ db: Database) throws {
        try db.create(table: "recurrence_rule") { t in
            t.column("recurrence_rule_id", .text).primaryKey()
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("frequency_kind", .text).notNull()
            t.column("interval", .integer)
            t.column("every_weekday", .boolean)
            t.column("days_of_week", .text)
            t.column("month", .integer)
            t.column("pattern_kind", .text)
            t.column("pattern_day_of_month", .integer)
            t.column("pattern_ordinal", .text)
            t.column("pattern_weekday", .integer)
            t.column("end_kind", .text).notNull()
            t.column("end_occurrences", .integer)
            t.column("end_date", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull()
        }

        try db.create(table: "recurrence_exception") { t in
            t.column("recurrence_exception_id", .text).primaryKey()
            t.column("recurrence_rule_id", .text).notNull().references("recurrence_rule", onDelete: .cascade)
            t.column("original_occurrence_date", .datetime).notNull()
            t.column("kind", .text).notNull()
            t.column("override_meeting_id", .text).references("meeting", onDelete: .setNull)
            t.column("override_scheduled_recording_id", .text)
                .references("scheduled_recording", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull()
        }

        try db.alter(table: "meeting") { t in
            t.add(column: "recurrence_rule_id", .text).references("recurrence_rule", onDelete: .setNull)
        }
        try db.alter(table: "scheduled_recording") { t in
            t.add(column: "recurrence_rule_id", .text).references("recurrence_rule", onDelete: .setNull)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.drop(column: "recurrence_rule_id")
        }
        try db.alter(table: "scheduled_recording") { t in
            t.drop(column: "recurrence_rule_id")
        }
        try db.drop(table: "recurrence_exception")
        try db.drop(table: "recurrence_rule")
    }
}
