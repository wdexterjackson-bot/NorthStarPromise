@preconcurrency import GRDB
import NSPCore

/// Deletes every `segment`/`transcript_turn`/`note_block`/`timeline_event`
/// row owned by `owner` — the explicit cleanup `Meeting`/`BrainDump`/`Note`
/// deletion each need now that those four tables are no longer a SQL
/// foreign key to a single parent table (`Migration012AddNotesAndBrainDumps`'s
/// own doc comment: a polymorphic owner can't be a real FK, so integrity
/// here is this function, not `ON DELETE CASCADE`). Each table's own
/// children (`transcript_token`, `note_operation`, etc.) still cascade
/// automatically off `turn_id`/`block_id`, which didn't change.
enum OwnedContentCleanup {
    static func deleteAll(for owner: ContentOwnerRef, in db: Database) throws {
        let encoded = ContentOwnerRefColumns.encode(owner)
        for table in ["segment", "transcript_turn", "note_block", "timeline_event"] {
            try db.execute(
                sql: "DELETE FROM \(table) WHERE meeting_id = ? AND owner_kind = ?",
                arguments: [encoded.id, encoded.kind])
        }
    }
}
