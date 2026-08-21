import GRDB

/// Converts any `meeting` row with `recording_intent = 'mentalNote'` into a
/// real `brain_dump` row — the data-side completion of retiring
/// `RecordingIntent.mentalNote` (docs/09-BACKLOG.md, "rescoping the
/// meeting-organization data model"): every mental note recorded before
/// that retirement is still sitting in `meeting` with a
/// `recording_intent` value `RecordingIntent` no longer has a case for,
/// which made `MeetingRow.asDomain()` throw `PersistenceError.corruptRow`
/// for it — surfaced as a real decode error on Dashboard load, not just a
/// theoretical gap.
///
/// Reuses the meeting's own id as the new `brain_dump_id` — both are
/// UUID-backed `TypedID`s, so `segment`/`transcript_turn`/`note_block`/
/// `timeline_event` rows that already point at this id only need their
/// `owner_kind` flipped from `'meeting'` to `'brainDump'`, never a new id
/// or a rewrite of the id column itself. Everything else that still has a
/// real FK to `meeting` (`consent_record`, `meeting_project`, any
/// `action_item`/`decision`/`insight`) cascades away with the deleted
/// `meeting` row — none of those concepts exist for a `BrainDump` yet
/// (Phase C's freestanding actions/threads hasn't landed), so there's
/// nothing meaningful to carry forward for them.
enum Migration014ConvertMentalNoteMeetings: SchemaMigration {
    static let identifier = "014_convertMentalNoteMeetings"

    static func up(_ db: Database) throws {
        let mentalNoteMeetingIDs = try String.fetchAll(
            db, sql: "SELECT meeting_id FROM meeting WHERE recording_intent = 'mentalNote'")
        for meetingID in mentalNoteMeetingIDs {
            try convertToBrainDump(meetingID, in: db)
        }
    }

    private static func convertToBrainDump(_ meetingID: String, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO brain_dump (
                    brain_dump_id, workspace_id, origin_device_id, started_at, ended_at,
                    canonical_duration_sample_count, canonical_duration_sample_rate, lifecycle_state,
                    lifecycle_state_failure_reason, policy_id, processing_mode, created_at, updated_at, row_revision
                )
                SELECT
                    meeting_id, workspace_id, origin_device_id, started_at, ended_at,
                    canonical_duration_sample_count, canonical_duration_sample_rate, lifecycle_state,
                    lifecycle_state_failure_reason, policy_id, processing_mode, created_at, updated_at, row_revision
                FROM meeting WHERE meeting_id = ?
                """, arguments: [meetingID])
        for table in ["segment", "transcript_turn", "note_block", "timeline_event"] {
            try db.execute(
                sql: "UPDATE \(table) SET owner_kind = 'brainDump' WHERE meeting_id = ? AND owner_kind = 'meeting'",
                arguments: [meetingID])
        }
        // Cascades away `consent_record`/`meeting_project`/any actions,
        // decisions, or insights this row had — this doc comment's own
        // header explains why that's the right outcome here.
        try db.execute(sql: "DELETE FROM meeting WHERE meeting_id = ?", arguments: [meetingID])
    }

    /// Deliberately a no-op, not a real reversal — `.mentalNote` doesn't
    /// exist as a `RecordingIntent` case any more, so restoring these rows
    /// as `meeting` rows with that value would just recreate the exact
    /// decode failure this migration exists to fix (same reasoning
    /// `Migration012AddNotesAndBrainDumps.down()` documents for its own
    /// unrecoverable rows).
    static func down(_ db: Database) throws {}
}
