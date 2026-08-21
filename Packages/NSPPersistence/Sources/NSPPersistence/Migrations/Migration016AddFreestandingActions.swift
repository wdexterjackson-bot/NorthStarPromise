import GRDB

/// Lets an `Action` exist without a `Meeting` — a freestanding commitment
/// the user owns directly, per the user's own distinction: an action item
/// is something they can act on themselves, unlike a `Thread`, which needs
/// coordinated effort across several meetings, emails, and people
/// (docs/09-BACKLOG.md, "rescoping the meeting-organization data model").
/// Also adds `Action.threadID`/`counterpartyID` and `Decision.threadID`.
///
/// `action_item.meeting_id` losing its `NOT NULL` needs the full
/// table-rebuild treatment (`Migration012AddNotesAndBrainDumps`'s own doc
/// comment: SQLite's `ALTER TABLE` can add/drop whole columns but never
/// change one's constraints) — unlike `Migration015`'s plain column drop,
/// this is a real constraint change, not just removing an FK. The new
/// `workspace_id` column is backfilled from each row's own meeting before
/// the constraint that makes that lookup possible (`meeting_id NOT NULL`)
/// is relaxed, so every pre-existing action keeps a real workspace even
/// though it's now nullable at the column level.
enum Migration016AddFreestandingActions: SchemaMigration {
    static let identifier = "016_addFreestandingActions"

    static func up(_ db: Database) throws {
        try rebuildActionItemTable(db)
        try db.alter(table: "decision") { t in
            t.add(column: "thread_id", .text).references("thread", onDelete: .setNull)
        }
    }

    private static func rebuildActionItemTable(_ db: Database) throws {
        try db.create(table: "action_item_new") { t in
            t.primaryKey("action_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("meeting_id", .text).references("meeting", onDelete: .cascade)
            t.column("thread_id", .text).references("thread", onDelete: .setNull)
            t.column("counterparty_id", .text).references("person", onDelete: .setNull)
            t.column("text", .text).notNull()
            t.column("owner_state", .text).notNull().defaults(to: "unresolved")
            t.column("owner_person_id", .text).references("person", onDelete: .setNull)
            t.column("date_state", .text).notNull().defaults(to: "unresolved")
            t.column("date_value", .datetime)
            t.column("status", .text).notNull().defaults(to: "proposed")
            t.column("destination", .text)
            t.column("direction", .text).notNull().defaults(to: "iOwe")
            t.column("defer_count", .integer).notNull().defaults(to: 0)
            t.column("asked_again_count", .integer).notNull().defaults(to: 0)
            t.column("confidence", .double).notNull().defaults(to: 1.0)
            t.column("edited", .boolean).notNull().defaults(to: false)
            t.column("created_by", .text).notNull().references("person")
            t.column("confirmed_by", .text).references("person")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }
        try db.execute(
            sql: """
                INSERT INTO action_item_new (
                    action_id, workspace_id, meeting_id, text, owner_state, owner_person_id, date_state,
                    date_value, status, destination, direction, defer_count, asked_again_count, confidence,
                    edited, created_by, confirmed_by, created_at, updated_at, row_revision, cloud_record_change_tag
                )
                SELECT
                    a.action_id, m.workspace_id, a.meeting_id, a.text, a.owner_state, a.owner_person_id,
                    a.date_state, a.date_value, a.status, a.destination, a.direction, a.defer_count,
                    a.asked_again_count, a.confidence, a.edited, a.created_by, a.confirmed_by, a.created_at,
                    a.updated_at, a.row_revision, a.cloud_record_change_tag
                FROM action_item a JOIN meeting m ON m.meeting_id = a.meeting_id
                """)
        try db.drop(table: "action_item")
        try db.rename(table: "action_item_new", to: "action_item")
    }

    /// Reverses the shape, not the data loss risk it implies: any action
    /// actually left freestanding (`meeting_id IS NULL`) has no meeting to
    /// re-derive `NOT NULL meeting_id` from and is dropped — there is no
    /// valid pre-migration row for it to become (same rule
    /// `Migration012AddNotesAndBrainDumps.down()` documents for its own
    /// unrecoverable rows).
    static func down(_ db: Database) throws {
        try db.alter(table: "decision") { t in
            t.drop(column: "thread_id")
        }
        try db.create(table: "action_item_old") { t in
            t.primaryKey("action_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("text", .text).notNull()
            t.column("owner_state", .text).notNull().defaults(to: "unresolved")
            t.column("owner_person_id", .text).references("person", onDelete: .setNull)
            t.column("date_state", .text).notNull().defaults(to: "unresolved")
            t.column("date_value", .datetime)
            t.column("status", .text).notNull().defaults(to: "proposed")
            t.column("destination", .text)
            t.column("created_by", .text).notNull().references("person")
            t.column("confirmed_by", .text).references("person")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
            t.column("direction", .text).notNull().defaults(to: "iOwe")
            t.column("defer_count", .integer).notNull().defaults(to: 0)
            t.column("asked_again_count", .integer).notNull().defaults(to: 0)
            t.column("confidence", .double).notNull().defaults(to: 1.0)
            t.column("edited", .boolean).notNull().defaults(to: false)
        }
        try db.execute(
            sql: """
                INSERT INTO action_item_old
                SELECT
                    action_id, meeting_id, text, owner_state, owner_person_id, date_state, date_value, status,
                    destination, created_by, confirmed_by, created_at, updated_at, row_revision,
                    cloud_record_change_tag, direction, defer_count, asked_again_count, confidence, edited
                FROM action_item WHERE meeting_id IS NOT NULL
                """)
        try db.drop(table: "action_item")
        try db.rename(table: "action_item_old", to: "action_item")
    }
}
