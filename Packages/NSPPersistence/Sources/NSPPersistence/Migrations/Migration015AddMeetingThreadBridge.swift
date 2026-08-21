import GRDB

/// Replaces the single nullable `meeting.thread_id` column
/// (`Migration010RenameThreadAndReshape`) with a many-to-many
/// `meeting_thread` join table — the user's explicit correction to the
/// Dashboard redesign's original "each meeting joins zero or one thread"
/// rule (docs/09-BACKLOG.md, "rescoping the meeting-organization data
/// model"): a meeting may now join several threads at once, mirroring
/// `meeting_project`'s exact shape (`Migration005AddProjects`).
///
/// `thread_id` is provably safe to drop via a plain `ALTER TABLE ... DROP
/// COLUMN` despite carrying a foreign key — `Migration010`'s own `down()`
/// already does exactly this, proving this SQLite/GRDB version supports it
/// without the full table-rebuild `Migration012`/`Migration013`/`Migration016`
/// need for a NOT NULL or type change.
enum Migration015AddMeetingThreadBridge: SchemaMigration {
    static let identifier = "015_addMeetingThreadBridge"

    static func up(_ db: Database) throws {
        try db.create(table: "meeting_thread") { t in
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
            t.primaryKey(["meeting_id", "thread_id"])
        }
        try db.execute(
            sql: """
                INSERT INTO meeting_thread (meeting_id, thread_id)
                SELECT meeting_id, thread_id FROM meeting WHERE thread_id IS NOT NULL
                """)
        try db.alter(table: "meeting") { t in
            t.drop(column: "thread_id")
        }
    }

    /// Best-effort, one thread per meeting — same "current usage is light
    /// enough this is safe" call `Migration010`'s own forward direction
    /// made for the reverse of this exact conversion.
    static func down(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.add(column: "thread_id", .text).references("thread", onDelete: .setNull)
        }
        try db.execute(
            sql: """
                UPDATE meeting SET thread_id = (
                    SELECT thread_id FROM meeting_thread
                    WHERE meeting_thread.meeting_id = meeting.meeting_id
                    LIMIT 1
                )
                """)
        try db.drop(table: "meeting_thread")
    }
}
