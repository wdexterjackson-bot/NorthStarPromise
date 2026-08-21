import GRDB

/// Populates the `fts_transcript`/`fts_notes`/`fts_insight` shells
/// `Migration001`'s `createFTS5Tables` left empty ("NSP-043 owns the
/// maintenance triggers" — this is that). Real SQL triggers, not an
/// app-level dual-write, per `docs/02-DATA-MODEL.md` §5's explicit
/// requirement: "FTS triggers exclude any meeting where
/// `excluded_from_memory = 1` or `deleted_at IS NOT NULL`" — i.e. exclusion
/// is enforced by the index itself, never by a query-time filter layered on
/// top (Ask's authorization-before-retrieval rule, docs/04 §10.2, depends
/// on this: the index must never contain a candidate a query could
/// accidentally forget to filter out).
///
/// GRDB has no typed trigger DSL, so this is raw `db.execute(sql:)` —
/// already this codebase's convention for anything the query builder
/// doesn't cover (see `GRDBMeetingRepository`'s missing-segment sync).
///
/// Each FTS table's population is delete-then-reinsert per source row,
/// converging correctly even though `TranscriptTurnRepository`/
/// `GRDBNoteBlockRepository` etc. write via their own "delete all children,
/// reinsert" pattern — the trigger churns per child row but always ends at
/// the right final state.
///
/// **Known gap, not solved here**: un-excluding a meeting
/// (`excluded_from_memory`/`deleted_at` transitioning back to eligible)
/// does not repopulate its FTS rows or embeddings — only the
/// exclude-transition purges. Rebuilding on reversal needs either a real
/// SQL rebuild-trigger (nontrivial for `fts_transcript`'s per-turn
/// aggregation) or an app-level re-index job; neither exists yet.
enum Migration004AddFTSTriggers: SchemaMigration {
    static let identifier = "004_addFTSTriggers"

    static func up(_ db: Database) throws {
        try createTranscriptTriggers(db)
        try createNoteTriggers(db)
        try createInsightTriggers(db)
        try createMeetingExclusionTrigger(db)
    }

    static func down(_ db: Database) throws {
        for trigger in [
            "trg_fts_transcript_token_ai", "trg_fts_transcript_token_ad", "trg_fts_notes_ai", "trg_fts_notes_au",
            "trg_fts_notes_au_nontext", "trg_fts_insight_ai", "trg_fts_insight_au",
            "trg_meeting_excluded_purges_index",
        ] {
            try db.execute(sql: "DROP TRIGGER IF EXISTS \(trigger)")
        }
    }

    private static func createTranscriptTriggers(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_transcript_token_ai AFTER INSERT ON transcript_token
                BEGIN
                    DELETE FROM fts_transcript WHERE turn_id = NEW.turn_id;
                    INSERT INTO fts_transcript (turn_id, meeting_id, body)
                    SELECT tt.turn_id, tt.meeting_id,
                        (SELECT group_concat(text, ' ') FROM
                            (SELECT text FROM transcript_token WHERE turn_id = NEW.turn_id ORDER BY position))
                    FROM transcript_turn tt
                    WHERE tt.turn_id = NEW.turn_id
                        AND NOT EXISTS (
                            SELECT 1 FROM meeting m
                            WHERE m.meeting_id = tt.meeting_id
                                AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                        );
                END
                """)
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_transcript_token_ad AFTER DELETE ON transcript_token
                BEGIN
                    DELETE FROM fts_transcript WHERE turn_id = OLD.turn_id;
                    INSERT INTO fts_transcript (turn_id, meeting_id, body)
                    SELECT tt.turn_id, tt.meeting_id,
                        (SELECT group_concat(text, ' ') FROM
                            (SELECT text FROM transcript_token WHERE turn_id = OLD.turn_id ORDER BY position))
                    FROM transcript_turn tt
                    WHERE tt.turn_id = OLD.turn_id
                        AND EXISTS (SELECT 1 FROM transcript_token WHERE turn_id = OLD.turn_id)
                        AND NOT EXISTS (
                            SELECT 1 FROM meeting m
                            WHERE m.meeting_id = tt.meeting_id
                                AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                        );
                END
                """)
    }

    private static func createNoteTriggers(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_notes_ai AFTER INSERT ON note_block
                WHEN NEW.content_kind = 'text'
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
                WHEN NEW.content_kind = 'text'
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
        // Defensive: if a block's content_kind ever changes away from
        // 'text', purge its stale FTS row rather than leaving it orphaned.
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_notes_au_nontext AFTER UPDATE OF content_kind ON note_block
                WHEN NEW.content_kind != 'text'
                BEGIN
                    DELETE FROM fts_notes WHERE block_id = NEW.block_id;
                END
                """)
    }

    private static func createInsightTriggers(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_insight_ai AFTER INSERT ON insight
                BEGIN
                    DELETE FROM fts_insight WHERE insight_id = NEW.insight_id;
                    INSERT INTO fts_insight (insight_id, meeting_id, body)
                    SELECT NEW.insight_id, NEW.meeting_id, NEW.text
                    WHERE NOT EXISTS (
                        SELECT 1 FROM meeting m
                        WHERE m.meeting_id = NEW.meeting_id AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                    );
                END
                """)
        try db.execute(
            sql: """
                CREATE TRIGGER trg_fts_insight_au AFTER UPDATE OF text, meeting_id ON insight
                BEGIN
                    DELETE FROM fts_insight WHERE insight_id = NEW.insight_id;
                    INSERT INTO fts_insight (insight_id, meeting_id, body)
                    SELECT NEW.insight_id, NEW.meeting_id, NEW.text
                    WHERE NOT EXISTS (
                        SELECT 1 FROM meeting m
                        WHERE m.meeting_id = NEW.meeting_id AND (m.excluded_from_memory = 1 OR m.deleted_at IS NOT NULL)
                    );
                END
                """)
    }

    /// Fires only on the transition *into* excluded/deleted — un-exclusion
    /// is the known, documented gap above, not handled here.
    private static func createMeetingExclusionTrigger(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TRIGGER trg_meeting_excluded_purges_index
                AFTER UPDATE OF excluded_from_memory, deleted_at ON meeting
                WHEN (NEW.excluded_from_memory = 1 OR NEW.deleted_at IS NOT NULL)
                    AND (OLD.excluded_from_memory = 0 AND OLD.deleted_at IS NULL)
                BEGIN
                    DELETE FROM fts_transcript WHERE meeting_id = NEW.meeting_id;
                    DELETE FROM fts_notes WHERE meeting_id = NEW.meeting_id;
                    DELETE FROM fts_insight WHERE meeting_id = NEW.meeting_id;
                    UPDATE embedding SET excluded_from_memory = 1 WHERE meeting_id = NEW.meeting_id;
                END
                """)
    }
}
