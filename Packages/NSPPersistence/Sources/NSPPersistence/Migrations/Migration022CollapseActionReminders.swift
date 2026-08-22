import GRDB

/// Collapses "Action Reminder" (a `Meeting` row with `kind = 'reminder'`,
/// never meant to record anything, just a title and time on the agenda)
/// into a plain freestanding `Action` — "The Spine" recommendation
/// (2026-08-22): now that `Action.counterpartyID`/`direction`/`date` are
/// wired up (People plan phase 1), a reminder living as a phantom Meeting
/// doesn't show up on a Person's page, doesn't count in Needs You, and
/// doesn't participate in any relationship query — the wrong home for it.
/// Converts every existing `.reminder` meeting into a due-dated, no-meeting
/// `Action` (title -> text, started_at -> date), then removes those rows —
/// `MeetingKind` itself drops the `.reminder` case in the same commit, so
/// this migration guarantees no row can still carry that string by the
/// time app code reads it.
enum Migration022CollapseActionReminders: SchemaMigration {
    static let identifier = "022_collapseActionReminders"

    static func up(_ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO action_item (
                    action_id, workspace_id, meeting_id, text, owner_state, date_state, date_value, status,
                    direction, defer_count, asked_again_count, confidence, edited, created_by, created_at,
                    updated_at, row_revision
                )
                SELECT
                    lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
                        substr(lower(hex(randomblob(2))), 2) || '-a' || substr(lower(hex(randomblob(2))), 2) ||
                        '-' || lower(hex(randomblob(6))),
                    m.workspace_id, NULL, m.title, 'unresolved', 'explicit', m.started_at, 'proposed', 'iOwe',
                    0, 0, 1.0, 0, (SELECT p.person_id FROM person p WHERE p.workspace_id = m.workspace_id LIMIT 1),
                    m.created_at, m.updated_at, 1
                FROM meeting m
                WHERE m.kind = 'reminder'
                  AND EXISTS (SELECT 1 FROM person p WHERE p.workspace_id = m.workspace_id)
                """)
        try db.execute(sql: "DELETE FROM meeting WHERE kind = 'reminder'")
    }

    /// Irreversible by design — same "no valid pre-migration row exists for
    /// a dropped concept" rule `Migration016`'s `down()` documents.
    static func down(_ db: Database) throws {}
}
