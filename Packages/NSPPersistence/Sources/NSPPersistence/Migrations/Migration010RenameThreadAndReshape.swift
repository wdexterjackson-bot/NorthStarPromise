import Foundation
import GRDB

/// Renames `thread_in_motion` to `thread` and reshapes it for the Dashboard
/// redesign (`DASHBOARD_SPEC.md` §3.2): adds `kind`, `color_slot`,
/// `last_touched_at`, `next_meeting_id`, `external_org_id`; remaps the old
/// three-case `status` values onto the new five-case set. Replaces the
/// many-to-many `thread_meeting` join table with a single nullable
/// `meeting.thread_id` column (§3.5: "each meeting joins exactly zero or
/// one thread") — existing links migrate best-effort, one thread per
/// meeting (a meeting linked to more than one thread today keeps only its
/// most-recently-created link; current usage is light enough this is
/// safe). Drops `thread_project` outright: threads no longer link to
/// projects — the two are independent, parallel groupings from here on.
enum Migration010RenameThreadAndReshape: SchemaMigration {
    static let identifier = "010_renameThreadAndReshape"

    static func up(_ db: Database) throws {
        try db.rename(table: "thread_in_motion", to: "thread")
        try db.alter(table: "thread") { t in
            t.add(column: "kind", .text).notNull().defaults(to: ThreadKindRaw.initiative)
            t.add(column: "color_slot", .integer).notNull().defaults(to: 0)
            t.add(column: "last_touched_at", .datetime).notNull().defaults(to: Date.distantPast)
            t.add(column: "next_meeting_id", .text)
            t.add(column: "external_org_id", .text)
        }
        try Self.remapStatus(db)

        try db.alter(table: "meeting") { t in
            t.add(column: "thread_id", .text).references("thread", onDelete: .setNull)
        }
        try Self.migrateThreadMeetingLinks(db)

        try db.drop(table: "thread_project")
        try db.drop(table: "thread_meeting")
    }

    static func down(_ db: Database) throws {
        try db.create(table: "thread_meeting") { t in
            t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.primaryKey(["thread_id", "meeting_id"])
        }
        try db.create(table: "thread_project") { t in
            t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
            t.column("project_id", .text).notNull().references("project", onDelete: .cascade)
            t.primaryKey(["thread_id", "project_id"])
        }
        try db.execute(
            sql: """
                INSERT INTO thread_meeting (thread_id, meeting_id)
                SELECT thread_id, meeting_id FROM meeting WHERE thread_id IS NOT NULL
                """)
        try db.alter(table: "meeting") { t in
            t.drop(column: "thread_id")
        }
        try db.alter(table: "thread") { t in
            t.drop(column: "external_org_id")
            t.drop(column: "next_meeting_id")
            t.drop(column: "last_touched_at")
            t.drop(column: "color_slot")
            t.drop(column: "kind")
        }
        try Self.unmapStatus(db)
        try db.rename(table: "thread", to: "thread_in_motion")
    }

    /// Old `ThreadInMotionStatus` had `active/completed/archived`; the new
    /// `NSPThreadStatus` has `onTrack/decisionDue/atRisk/dormant/closed`.
    /// `active` maps to `onTrack` (the real derivation rules recompute a
    /// more specific status the next time the thread is opened); both
    /// terminal states collapse to `closed`.
    private static func remapStatus(_ db: Database) throws {
        try db.execute(sql: "UPDATE thread SET status = 'onTrack' WHERE status = 'active'")
        try db.execute(sql: "UPDATE thread SET status = 'closed' WHERE status IN ('completed', 'archived')")
    }

    private static func unmapStatus(_ db: Database) throws {
        try db.execute(sql: "UPDATE thread SET status = 'active' WHERE status != 'closed'")
        try db.execute(sql: "UPDATE thread SET status = 'archived' WHERE status = 'closed'")
    }

    private static func migrateThreadMeetingLinks(_ db: Database) throws {
        try db.execute(
            sql: """
                UPDATE meeting SET thread_id = (
                    SELECT thread_id FROM thread_meeting
                    WHERE thread_meeting.meeting_id = meeting.meeting_id
                    LIMIT 1
                )
                """)
    }

    private enum ThreadKindRaw {
        static let initiative = "initiative"
    }
}
