import GRDB

/// Adds `Note` and `BrainDump` as real top-level entities — not disguised
/// `Meeting` rows — and makes `segment`/`transcript_turn`/`note_block`
/// polymorphic over which of the three owns them (docs/09-BACKLOG.md,
/// "rescoping the meeting-organization data model": a Brain Dump is a
/// recording that isn't a meeting; a Note isn't a meeting even when it
/// carries a recording).
///
/// SQLite's `ALTER TABLE` can't drop or change a column's constraints —
/// only rename/add/drop whole columns — so making `meeting_id` stop being a
/// foreign key on these three tables means rebuilding each one: create a
/// replacement table with the same columns plus `owner_kind`, copy every
/// row across (existing rows all get `owner_kind = 'meeting'`, since that's
/// the only owner kind that existed before this migration), drop the
/// original, rename the replacement into its place. This migration's
/// `foreignKeyChecks` stay at `AppDatabase`'s default (`.deferred`), so the
/// moment where `segment`/`transcript_turn`/`note_block` don't exist mid-
/// migration never trips a foreign-key violation from the tables that
/// reference them (`transcript_turn_segment`, `transcript_token`, etc.) —
/// checks only run once against the final state, at commit.
enum Migration012AddNotesAndBrainDumps: SchemaMigration {
    static let identifier = "012_addNotesAndBrainDumps"

    static func up(_ db: Database) throws {
        try createBrainDumpTable(db)
        try createNoteTable(db)
        try rebuildSegmentTable(db)
        try rebuildTranscriptTurnTable(db)
        try rebuildNoteBlockTable(db)
        // `Migration004AddFTSTriggers`'s three `note_block` triggers
        // (`trg_fts_notes_*`) were created directly on that table — dropping
        // it above (the only way to change a column's constraints in
        // SQLite) silently destroyed them too; a rename doesn't restore a
        // dropped table's triggers. `transcript_token`'s and `insight`'s own
        // FTS triggers are unaffected: they're defined on tables this
        // migration never touches, and `transcript_token`'s trigger body
        // referencing `transcript_turn` by name still resolves correctly
        // once the rebuilt table exists under the same name again.
        try recreateNoteBlockFTSTriggers(db)
    }

    /// Reverses the table shape, not the data: any row actually owned by a
    /// `BrainDump`/`Note` (impossible before this migration existed, so only
    /// reachable if this migration is rolled back after real use) has no
    /// meaning in the pre-migration schema and is dropped along with
    /// `brain_dump`/`note` themselves — there is no `Meeting` for it to
    /// become.
    static func down(_ db: Database) throws {
        try restoreSegmentTable(db)
        try restoreTranscriptTurnTable(db)
        try restoreNoteBlockTable(db)
        try recreateNoteBlockFTSTriggers(db)
        try db.drop(table: "note")
        try db.drop(table: "brain_dump")
    }

    private static func createBrainDumpTable(_ db: Database) throws {
        try db.create(table: "brain_dump") { t in
            t.primaryKey("brain_dump_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("origin_device_id", .text).notNull()
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("canonical_duration_sample_count", .integer).notNull().defaults(to: 0)
            t.column("canonical_duration_sample_rate", .integer).notNull().defaults(to: 0)
            t.column("lifecycle_state", .text).notNull()
            t.column("lifecycle_state_failure_reason", .text)
            t.column("policy_id", .text).notNull().references("policy")
            t.column("processing_mode", .text).notNull()
            t.column("consent_record_id", .text)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("deleted_at", .datetime)
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }
    }

    private static func createNoteTable(_ db: Database) throws {
        try db.create(table: "note") { t in
            t.primaryKey("note_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("origin_device_id", .text)
            t.column("consent_record_id", .text)
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("canonical_duration_sample_count", .integer).notNull().defaults(to: 0)
            t.column("canonical_duration_sample_rate", .integer).notNull().defaults(to: 0)
            t.column("lifecycle_state", .text).notNull()
            t.column("lifecycle_state_failure_reason", .text)
            t.column("policy_id", .text).notNull().references("policy")
            t.column("processing_mode", .text).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("deleted_at", .datetime)
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }
    }

    private static func rebuildSegmentTable(_ db: Database) throws {
        try db.create(table: "segment_new") { t in
            t.primaryKey("segment_id", .text)
            t.column("meeting_id", .text).notNull()
            t.column("owner_kind", .text).notNull().defaults(to: "meeting")
            t.column("device_id", .text).notNull()
            t.column("sequence", .integer).notNull()
            t.column("codec", .text).notNull()
            t.column("sample_rate", .integer).notNull()
            t.column("channels", .integer).notNull()
            t.column("bit_rate", .integer).notNull()
            t.column("start_sample", .integer).notNull()
            t.column("sample_count", .integer).notNull()
            t.column("sha256", .text)
            t.column("local_url", .text)
            t.column("cloud_asset_ref", .text)
            t.column("transfer_state", .text).notNull()
            t.column("transfer_state_failure_reason", .text)
            t.column("is_repaired_tail", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
            t.uniqueKey(["meeting_id", "device_id", "sequence"])
        }
        try db.execute(
            sql: """
                INSERT INTO segment_new (
                    segment_id, meeting_id, owner_kind, device_id, sequence, codec, sample_rate, channels,
                    bit_rate, start_sample, sample_count, sha256, local_url, cloud_asset_ref, transfer_state,
                    transfer_state_failure_reason, is_repaired_tail, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                )
                SELECT
                    segment_id, meeting_id, 'meeting', device_id, sequence, codec, sample_rate, channels,
                    bit_rate, start_sample, sample_count, sha256, local_url, cloud_asset_ref, transfer_state,
                    transfer_state_failure_reason, is_repaired_tail, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                FROM segment
                """)
        try db.drop(table: "segment")
        try db.rename(table: "segment_new", to: "segment")
    }

    private static func rebuildTranscriptTurnTable(_ db: Database) throws {
        try db.create(table: "transcript_turn_new") { t in
            t.primaryKey("turn_id", .text)
            t.column("meeting_id", .text).notNull()
            t.column("owner_kind", .text).notNull().defaults(to: "meeting")
            t.column("revision", .integer).notNull()
            t.column("is_provisional", .boolean).notNull().defaults(to: false)
            t.column("speaker_cluster_id", .text)
                .references("speaker_cluster", column: "cluster_id", onDelete: .setNull)
            t.column("person_id", .text).references("person", onDelete: .setNull)
            t.column("edit_state", .text).notNull()
            t.column("edit_state_revision_of", .integer)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }
        try db.execute(
            sql: """
                INSERT INTO transcript_turn_new (
                    turn_id, meeting_id, owner_kind, revision, is_provisional, speaker_cluster_id, person_id,
                    edit_state, edit_state_revision_of, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                )
                SELECT
                    turn_id, meeting_id, 'meeting', revision, is_provisional, speaker_cluster_id, person_id,
                    edit_state, edit_state_revision_of, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                FROM transcript_turn
                """)
        try db.drop(table: "transcript_turn")
        try db.rename(table: "transcript_turn_new", to: "transcript_turn")
    }

    private static func rebuildNoteBlockTable(_ db: Database) throws {
        try db.create(table: "note_block_new") { t in
            t.primaryKey("block_id", .text)
            t.column("meeting_id", .text).notNull()
            t.column("owner_kind", .text).notNull().defaults(to: "meeting")
            t.column("author_id", .text).notNull().references("person")
            t.column("type", .text).notNull()
            t.column("content_kind", .text).notNull()
            t.column("content_text", .text)
            t.column("content_asset_path", .text)
            t.column("creation_range_start_sample", .integer).notNull()
            t.column("creation_range_end_sample", .integer).notNull()
            t.column("privacy", .text).notNull()
            t.column("merge_state", .text).notNull()
            t.column("merge_state_diff_id", .text)
            t.column("merge_state_insight_id", .text)
                .references("insight", column: "insight_id", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }
        try db.execute(
            sql: """
                INSERT INTO note_block_new (
                    block_id, meeting_id, owner_kind, author_id, type, content_kind, content_text,
                    content_asset_path, creation_range_start_sample, creation_range_end_sample, privacy,
                    merge_state, merge_state_diff_id, merge_state_insight_id, created_at, updated_at,
                    row_revision, cloud_record_change_tag
                )
                SELECT
                    block_id, meeting_id, 'meeting', author_id, type, content_kind, content_text,
                    content_asset_path, creation_range_start_sample, creation_range_end_sample, privacy,
                    merge_state, merge_state_diff_id, merge_state_insight_id, created_at, updated_at,
                    row_revision, cloud_record_change_tag
                FROM note_block
                """)
        try db.drop(table: "note_block")
        try db.rename(table: "note_block_new", to: "note_block")
    }

    /// Verbatim copy of `Migration004AddFTSTriggers.createNoteTriggers`'s
    /// three triggers — that migration's own `note_block` triggers were
    /// destroyed by this one's table rebuild (this file's own top-level doc
    /// comment), so they're recreated here rather than left silently
    /// missing. Deliberately not a call back into `Migration004`'s private
    /// method: migrations never call into other migrations, each stays a
    /// frozen, standalone record of exactly what it did (docs/02 §1).
    private static func recreateNoteBlockFTSTriggers(_ db: Database) throws {
        // `AND NEW.owner_kind = 'meeting'` (new, vs. Migration004's original):
        // for a `BrainDump`/`Note`-owned block, `NEW.meeting_id` holds that
        // owner's id, not a real `meeting` row, so the exclusion subquery
        // below would never match and the guard would silently no-op rather
        // than actually gating anything — excluding those owner kinds here
        // instead of indexing them un-gated. Real FTS support for those two
        // owner kinds is follow-up work once they get their own
        // notes/processing UI.
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_notes_ai AFTER INSERT ON note_block
                WHEN NEW.content_kind = 'text' AND NEW.owner_kind = 'meeting'
                BEGIN
                    DELETE FROM fts_notes WHERE block_id = NEW.block_id;
                    INSERT INTO fts_notes (block_id, meeting_id, body)
                    SELECT NEW.block_id, NEW.meeting_id, NEW.content_text
                    WHERE NOT EXISTS (
                        SELECT 1 FROM meeting m
                        WHERE m.meeting_id = NEW.meeting_id AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                    );
                END
                """)
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_notes_au AFTER UPDATE OF content_kind, content_text, meeting_id ON note_block
                WHEN NEW.content_kind = 'text' AND NEW.owner_kind = 'meeting'
                BEGIN
                    DELETE FROM fts_notes WHERE block_id = NEW.block_id;
                    INSERT INTO fts_notes (block_id, meeting_id, body)
                    SELECT NEW.block_id, NEW.meeting_id, NEW.content_text
                    WHERE NOT EXISTS (
                        SELECT 1 FROM meeting m
                        WHERE m.meeting_id = NEW.meeting_id AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                    );
                END
                """)
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_notes_au_nontext AFTER UPDATE OF content_kind ON note_block
                WHEN NEW.content_kind != 'text'
                BEGIN
                    DELETE FROM fts_notes WHERE block_id = NEW.block_id;
                END
                """)
    }

}

/// Rollback-only table restorations, split from the main enum body purely to
/// stay under SwiftLint's `type_body_length` budget — `down(_:)` above calls
/// straight across this file boundary since these are still the same
/// migration, not a second one (docs/02 §1: one migration is one frozen
/// record of what it did, and splitting its rollback path across files would
/// blur that).
extension Migration012AddNotesAndBrainDumps {
    fileprivate static func restoreSegmentTable(_ db: Database) throws {
        try db.create(table: "segment_old") { t in
            t.primaryKey("segment_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("device_id", .text).notNull()
            t.column("sequence", .integer).notNull()
            t.column("codec", .text).notNull()
            t.column("sample_rate", .integer).notNull()
            t.column("channels", .integer).notNull()
            t.column("bit_rate", .integer).notNull()
            t.column("start_sample", .integer).notNull()
            t.column("sample_count", .integer).notNull()
            t.column("sha256", .text)
            t.column("local_url", .text)
            t.column("cloud_asset_ref", .text)
            t.column("transfer_state", .text).notNull()
            t.column("transfer_state_failure_reason", .text)
            t.column("is_repaired_tail", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
            t.uniqueKey(["meeting_id", "device_id", "sequence"])
        }
        try db.execute(
            sql: """
                INSERT INTO segment_old
                SELECT
                    segment_id, meeting_id, device_id, sequence, codec, sample_rate, channels, bit_rate,
                    start_sample, sample_count, sha256, local_url, cloud_asset_ref, transfer_state,
                    transfer_state_failure_reason, is_repaired_tail, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                FROM segment WHERE owner_kind = 'meeting'
                """)
        try db.drop(table: "segment")
        try db.rename(table: "segment_old", to: "segment")
    }

    fileprivate static func restoreTranscriptTurnTable(_ db: Database) throws {
        try db.create(table: "transcript_turn_old") { t in
            t.primaryKey("turn_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("revision", .integer).notNull()
            t.column("is_provisional", .boolean).notNull().defaults(to: false)
            t.column("speaker_cluster_id", .text)
                .references("speaker_cluster", column: "cluster_id", onDelete: .setNull)
            t.column("person_id", .text).references("person", onDelete: .setNull)
            t.column("edit_state", .text).notNull()
            t.column("edit_state_revision_of", .integer)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }
        try db.execute(
            sql: """
                INSERT INTO transcript_turn_old
                SELECT
                    turn_id, meeting_id, revision, is_provisional, speaker_cluster_id, person_id, edit_state,
                    edit_state_revision_of, created_at, updated_at, row_revision, cloud_record_change_tag
                FROM transcript_turn WHERE owner_kind = 'meeting'
                """)
        try db.drop(table: "transcript_turn")
        try db.rename(table: "transcript_turn_old", to: "transcript_turn")
    }

    fileprivate static func restoreNoteBlockTable(_ db: Database) throws {
        try db.create(table: "note_block_old") { t in
            t.primaryKey("block_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("author_id", .text).notNull().references("person")
            t.column("type", .text).notNull()
            t.column("content_kind", .text).notNull()
            t.column("content_text", .text)
            t.column("content_asset_path", .text)
            t.column("creation_range_start_sample", .integer).notNull()
            t.column("creation_range_end_sample", .integer).notNull()
            t.column("privacy", .text).notNull()
            t.column("merge_state", .text).notNull()
            t.column("merge_state_diff_id", .text)
            t.column("merge_state_insight_id", .text)
                .references("insight", column: "insight_id", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }
        try db.execute(
            sql: """
                INSERT INTO note_block_old
                SELECT
                    block_id, meeting_id, author_id, type, content_kind, content_text, content_asset_path,
                    creation_range_start_sample, creation_range_end_sample, privacy, merge_state,
                    merge_state_diff_id, merge_state_insight_id, created_at, updated_at, row_revision,
                    cloud_record_change_tag
                FROM note_block WHERE owner_kind = 'meeting'
                """)
        try db.drop(table: "note_block")
        try db.rename(table: "note_block_old", to: "note_block")
    }
}
