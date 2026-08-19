import GRDB

// swiftlint:disable file_length type_body_length function_body_length
// A migration is a single, self-contained historical record — once shipped
// it is never edited (docs/02 §1, docs/11 §8) — so splitting `up()`'s ~35
// `db.create(table:)` calls across files would only scatter one atomic unit
// without reducing its real complexity, which is schema v1 itself.

/// Schema v1 (docs/02 §5): one table per entity in docs/02 §2, plus the
/// normalization tables Swift's array-valued properties need, plus the three
/// FTS5 shells NSP-043 populates.
///
/// Column conventions used throughout:
/// - Every entity table has `created_at`, `updated_at`, `row_revision`
///   (docs/02 §5: "revision, bumped on write" — named `row_revision` here so
///   it never collides with a domain field that happens to also be called
///   `revision`, e.g. `transcript_turn.revision`), and `cloud_record_change_tag`
///   where the entity syncs to CloudKit (docs/02 §6).
/// - Pure join/normalization tables (arrays exploded into child rows) skip
///   that bookkeeping — they have no independent lifecycle; deleting the
///   parent row cascades to them.
/// - An enum field with an associated value gets a `<field>` discriminator
///   column plus one or more nullable `<field>_...` columns for the payload,
///   except `TimelineEventType`, whose payload shape varies per case and is
///   stored as `type_detail_json` instead of six mostly-empty columns.
/// - `speaker_cluster`, `sync_state`, `tombstone`, and `embedding` have no
///   owning Swift type in `NSPCore` yet (they belong to `NSPIntelligence` /
///   `NSPSync` / `NSPPolicy` per docs/01 §3). docs/02 §5 still names them as
///   part of schema v1, so they exist here in a deliberately minimal shape;
///   expect a follow-up migration once NSP-075/089/133/NSPSync's
///   change-token loop land and need more from them.
enum Migration001InitialSchema: SchemaMigration {
    static let identifier = "001_initialSchema"

    static func up(_ db: Database) throws {
        try createWorkspaceAndPolicyTables(db)
        try createMeetingTables(db)
        try createCaptureTables(db)
        try createTranscriptTables(db)
        try createNoteTables(db)
        try createInsightAndEvidenceTables(db)
        try createActionTables(db)
        try createDecisionTables(db)
        try createSupportingEntityTables(db)
        try createForwardLookingTables(db)
        try createFTS5Tables(db)
    }

    static func down(_ db: Database) throws {
        // NOT simply the reverse of `up`'s creation order: five columns
        // forward-reference a table created later (see the `references`
        // call sites above), so a table can depend on one created after it.
        // This is a real topological order over the FK graph — a table is
        // listed only once every table with a column referencing it has
        // already been dropped.
        for table in [
            // Leaves: nothing references these.
            "person_alias", "policy_blocked_domain", "policy_blocked_location",
            "meeting_missing_segment", "consent_record_participant", "workspace_member",
            "transcript_token", "transcript_language_span", "transcript_turn_segment",
            "note_operation", "evidence_span_turn",
            "action_dependency", "action_audit_entry", "decision_alternative", "decision_audit_entry",
            "glossary_entry_pronunciation_hint", "integration_retry",
            "audit_event", "share_grant", "embedding", "sync_state", "tombstone", "timeline_event",
            "fts_transcript", "fts_notes", "fts_insight",
            // Now-unblocked, one layer up.
            "segment", "transcript_turn", "glossary_entry", "integration_receipt", "note_block", "evidence_span",
            // Now-unblocked again.
            "speaker_cluster", "insight", "action_item", "decision",
        ] {
            try db.drop(table: table)
        }

        // `meeting` and `consent_record` reference each other (see the `up`
        // comment on `meeting.consent_record_id`) — a genuine cycle that no
        // drop order alone resolves. Break it by dropping the FK-bearing
        // column before either table, then both are free to drop normally.
        try db.alter(table: "meeting") { t in t.drop(column: "consent_record_id") }

        for table in ["consent_record", "person", "meeting", "policy", "workspace"] {
            try db.drop(table: table)
        }
    }

    // MARK: - Workspace, person, policy

    private static func createWorkspaceAndPolicyTables(_ db: Database) throws {
        try db.create(table: "workspace") { t in
            t.primaryKey("workspace_id", .text)
            t.column("name", .text).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        try db.create(table: "person") { t in
            t.primaryKey("person_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("voice_enrollment_ref", .text)
            t.column("contact_link", .text)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `Person.aliases` ([String]).
        try db.create(table: "person_alias") { t in
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("alias", .text).notNull()
            t.primaryKey(["person_id", "position"])
        }

        try db.create(table: "policy") { t in
            t.primaryKey("policy_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("retention_days", .integer)
            t.column("default_processing_mode", .text).notNull()
            t.column("announcement_required", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `Policy.blockedDomains` / `.blockedLocations` ([String] each).
        try db.create(table: "policy_blocked_domain") { t in
            t.column("policy_id", .text).notNull().references("policy", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("domain", .text).notNull()
            t.primaryKey(["policy_id", "position"])
        }
        try db.create(table: "policy_blocked_location") { t in
            t.column("policy_id", .text).notNull().references("policy", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("location", .text).notNull()
            t.primaryKey(["policy_id", "position"])
        }
    }

    // MARK: - Meeting, consent

    private static func createMeetingTables(_ db: Database) throws {
        // `meeting.consent_record_id` and `consent_record.meeting_id` point
        // at each other (a meeting has ≤1 consent record; a consent record
        // belongs to exactly one meeting). SQLite resolves forward-referenced
        // FK targets by name, not by creation order, so this cycle is fine —
        // `consent_record` need not exist yet when `meeting` is created.
        try db.create(table: "meeting") { t in
            t.primaryKey("meeting_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("is_title_sensitive", .boolean).notNull().defaults(to: false)
            t.column("calendar_event_id", .text)
            t.column("capture_mode", .text).notNull()
            t.column("origin_device_id", .text).notNull()
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("canonical_duration_sample_count", .integer).notNull().defaults(to: 0)
            t.column("canonical_duration_sample_rate", .integer).notNull().defaults(to: 1)
            t.column("lifecycle_state", .text).notNull()
            t.column("lifecycle_state_failure_reason", .text)
            t.column("policy_id", .text).notNull().references("policy")
            t.column("processing_mode", .text).notNull()
            // `column:` given explicitly — `consent_record` doesn't exist
            // yet, so GRDB can't introspect its primary key to infer it.
            t.column("consent_record_id", .text)
                .references("consent_record", column: "consent_record_id", onDelete: .setNull)
            t.column("availability", .text).notNull()
            t.column("excluded_from_memory", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("deleted_at", .datetime)
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `Availability.partial(missing: [SegmentRef])`.
        try db.create(table: "meeting_missing_segment") { t in
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            // Deliberately not a FK to `segment`: a missing segment is, by
            // definition, not present in this device's `segment` table yet.
            t.column("segment_id", .text).notNull()
            t.column("device_id", .text).notNull()
            t.column("sequence", .integer).notNull()
            t.primaryKey(["meeting_id", "segment_id"])
        }

        try db.create(table: "consent_record") { t in
            t.primaryKey("consent_record_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("method", .text).notNull()
            t.column("timestamp", .datetime).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        // `ConsentRecord.participantsAcknowledged` ([PersonID]).
        try db.create(table: "consent_record_participant") { t in
            t.column("consent_record_id", .text).notNull().references("consent_record", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["consent_record_id", "person_id"])
        }

        // `Workspace.memberPersonIDs` ([PersonID]).
        try db.create(table: "workspace_member") { t in
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["workspace_id", "person_id"])
        }
    }

    // MARK: - Capture: segment, timeline event

    private static func createCaptureTables(_ db: Database) throws {
        try db.create(table: "segment") { t in
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

        // Append-only (docs/02 §2: "makes the timeline explainable") — no
        // `deleted_at`; `sample_offset`, not `wall_clock`, is the only
        // ordering key that matters (docs/03 §4).
        try db.create(table: "timeline_event") { t in
            t.primaryKey("event_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("device_id", .text).notNull()
            t.column("type", .text).notNull()
            t.column("type_detail_json", .text)
            t.column("sample_offset", .integer).notNull()
            t.column("wall_clock", .datetime).notNull()
            t.column("payload_json", .text)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }
    }

    // MARK: - Transcript

    private static func createTranscriptTables(_ db: Database) throws {
        try db.create(table: "transcript_turn") { t in
            t.primaryKey("turn_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            // Domain field, not the bookkeeping counter: provisional
            // revisions are negative, canonical starts at 1 (docs/02 §2).
            t.column("revision", .integer).notNull()
            t.column("is_provisional", .boolean).notNull().defaults(to: false)
            // `column:` explicit — `speaker_cluster` doesn't exist yet.
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

        // `TranscriptTurn.tokens` ([Token]) — word-level timing, mandatory
        // for tap-to-audio, evidence, and redaction (docs/02 §2).
        try db.create(table: "transcript_token") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("turn_id", .text).notNull().references("transcript_turn", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("text", .text).notNull()
            t.column("start_sample", .integer).notNull()
            t.column("end_sample", .integer).notNull()
            t.column("confidence", .double).notNull()
            t.column("language_tag", .text)
            t.uniqueKey(["turn_id", "position"])
        }

        // `TranscriptTurn.languageSpans` ([LanguageSpan]).
        try db.create(table: "transcript_language_span") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("turn_id", .text).notNull().references("transcript_turn", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("language_tag", .text).notNull()
            t.column("start_sample", .integer).notNull()
            t.column("end_sample", .integer).notNull()
        }

        // `TranscriptTurn.segmentRefs` ([SegmentID]) — which audio backs
        // this turn.
        try db.create(table: "transcript_turn_segment") { t in
            t.column("turn_id", .text).notNull().references("transcript_turn", onDelete: .cascade)
            t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["turn_id", "segment_id"])
        }
    }

    // MARK: - Notes

    private static func createNoteTables(_ db: Database) throws {
        // `merge_state_insight_id` forward-references `insight`, created
        // later in this migration — allowed, see the `meeting`/
        // `consent_record` comment above.
        try db.create(table: "note_block") { t in
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
            // `column:` explicit — `insight` doesn't exist yet.
            t.column("merge_state_insight_id", .text)
                .references("insight", column: "insight_id", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `NoteBlock.opLog` ([Operation]) — conflict-resilient merge log
        // (docs/02 §2).
        try db.create(table: "note_operation") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("block_id", .text).notNull().references("note_block", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("author_id", .text).notNull().references("person")
            t.column("timestamp", .integer).notNull()
            t.column("content_kind", .text).notNull()
            t.column("content_text", .text)
            t.column("content_asset_path", .text)
        }
    }

    // MARK: - Insight, evidence

    private static func createInsightAndEvidenceTables(_ db: Database) throws {
        try db.create(table: "insight") { t in
            t.primaryKey("insight_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("layer", .text).notNull()
            t.column("text", .text).notNull()
            t.column("claim_kind", .text).notNull()
            t.column("confidence", .double).notNull()
            t.column("provenance_model_id", .text).notNull()
            t.column("provenance_model_version", .text).notNull()
            t.column("provenance_prompt_version", .text).notNull()
            t.column("provenance_template_id", .text)
            t.column("provenance_template_version", .text)
            t.column("provenance_generated_at", .datetime).notNull()
            t.column("provenance_processing_plane", .text).notNull()
            t.column("approval_state", .text).notNull().defaults(to: "draft")
            t.column("supersedes", .text).references("insight", onDelete: .setNull)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // Shared by `Insight.evidence`, `Action.evidence`, and
        // `Decision.evidence` — exactly one owner per span (Invariant I4).
        // `action_id`/`decision_id` forward-reference tables created later
        // in this migration.
        try db.create(table: "evidence_span") { t in
            t.autoIncrementedPrimaryKey("evidence_span_id")
            t.column("insight_id", .text).references("insight", onDelete: .cascade)
            // `column:` explicit on both — `action_item`/`decision` don't
            // exist yet.
            t.column("action_id", .text).references("action_item", column: "action_id", onDelete: .cascade)
            t.column("decision_id", .text).references("decision", column: "decision_id", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("sample_start", .integer).notNull()
            t.column("sample_end", .integer).notNull()
            t.column("quoted_text", .text).notNull()
            t.column("transcript_revision", .integer).notNull()
            t.check(
                sql: """
                    (insight_id IS NOT NULL) + (action_id IS NOT NULL) + (decision_id IS NOT NULL) = 1
                    """)
        }

        // `EvidenceSpan.turnIDs` ([TranscriptTurnID]).
        try db.create(table: "evidence_span_turn") { t in
            t.column("evidence_span_id", .integer).notNull().references("evidence_span", onDelete: .cascade)
            t.column("turn_id", .text).notNull().references("transcript_turn", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["evidence_span_id", "turn_id"])
        }
    }

    // MARK: - Actions

    private static func createActionTables(_ db: Database) throws {
        // Named `action_item`, not `action` (docs/02 §5, verbatim) — SQL
        // dialects reserve `ACTION` as a keyword in foreign-key clauses
        // (`ON DELETE ACTION`-adjacent grammar); this sidesteps it entirely.
        try db.create(table: "action_item") { t in
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
        }

        // `Action.dependencies` ([ActionID]).
        try db.create(table: "action_dependency") { t in
            t.column("action_id", .text).notNull().references("action_item", onDelete: .cascade)
            t.column("depends_on_action_id", .text).notNull().references("action_item", onDelete: .cascade)
            t.primaryKey(["action_id", "depends_on_action_id"])
        }

        // `Action.auditTrail` ([AuditEntry]). `action_text` (not `action`,
        // the SQL-reserved-adjacent word) mirrors `AuditEntry.action`.
        try db.create(table: "action_audit_entry") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("action_id", .text).notNull().references("action_item", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("actor_id", .text).notNull().references("person")
            t.column("action_text", .text).notNull()
            t.column("at", .datetime).notNull()
            t.column("detail", .text)
        }
    }

    // MARK: - Decisions

    private static func createDecisionTables(_ db: Database) throws {
        try db.create(table: "decision") { t in
            t.primaryKey("decision_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("text", .text).notNull()
            t.column("approver_state", .text).notNull().defaults(to: "unresolved")
            t.column("approver_person_id", .text).references("person", onDelete: .setNull)
            t.column("status", .text).notNull().defaults(to: "proposed")
            t.column("rationale", .text)
            t.column("supersedes", .text).references("decision", onDelete: .setNull)
            t.column("created_by", .text).notNull().references("person")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `Decision.alternativesConsidered` ([String]).
        try db.create(table: "decision_alternative") { t in
            t.column("decision_id", .text).notNull().references("decision", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("text", .text).notNull()
            t.primaryKey(["decision_id", "position"])
        }

        // `Decision.auditTrail` ([AuditEntry]).
        try db.create(table: "decision_audit_entry") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("decision_id", .text).notNull().references("decision", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("actor_id", .text).notNull().references("person")
            t.column("action_text", .text).notNull()
            t.column("at", .datetime).notNull()
            t.column("detail", .text)
        }
    }

    // MARK: - Speaker clusters, glossary, sharing, integrations, audit

    private static func createSupportingEntityTables(_ db: Database) throws {
        try db.create(table: "speaker_cluster") { t in
            t.primaryKey("cluster_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("person_id", .text).references("person", onDelete: .setNull)
            t.column("embedding_centroid", .blob)
            t.column("total_speech_samples", .integer).notNull().defaults(to: 0)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        try db.create(table: "glossary_entry") { t in
            t.primaryKey("glossary_entry_id", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("term", .text).notNull()
            t.column("origin", .text).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        // `GlossaryEntry.pronunciationHints` ([String]).
        try db.create(table: "glossary_entry_pronunciation_hint") { t in
            t.column("glossary_entry_id", .text).notNull().references("glossary_entry", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("hint", .text).notNull()
            t.primaryKey(["glossary_entry_id", "position"])
        }

        try db.create(table: "share_grant") { t in
            t.primaryKey("share_grant_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("recipient", .text).notNull()
            t.column("role", .text).notNull()
            t.column("scope", .text).notNull()
            t.column("expires_at", .datetime)
            t.column("passcode_hash", .text)
            t.column("download_policy", .text).notNull()
            t.column("revoked", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.column("cloud_record_change_tag", .text)
        }

        try db.create(table: "integration_receipt") { t in
            t.primaryKey("integration_receipt_id", .text)
            t.column("destination", .text).notNull()
            t.column("external_id", .text)
            t.column("idempotency_key", .text).notNull().unique()
            t.column("request_hash", .text).notNull()
            // `IntegrationReceipt.response` (0-or-1 `IntegrationResponse`)
            // flattened rather than a child table.
            t.column("response_succeeded", .boolean)
            t.column("response_status_description", .text)
            t.column("response_received_at", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        // `IntegrationReceipt.retryHistory` ([IntegrationRetry]).
        try db.create(table: "integration_retry") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("integration_receipt_id", .text).notNull()
                .references("integration_receipt", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("attempted_at", .datetime).notNull()
            t.column("succeeded", .boolean).notNull()
            t.column("status_description", .text).notNull()
            t.column("received_at", .datetime).notNull()
        }

        // Append-only workspace-wide ledger (docs/06 §11: "Append-only,
        // admin-exportable; deleting content never deletes the audit
        // trail") — no `updated_at`/`row_revision`, rows are never mutated.
        try db.create(table: "audit_event") { t in
            t.primaryKey("audit_event_id", .text)
            t.column("actor_id", .text).references("person", onDelete: .setNull)
            t.column("action", .text).notNull()
            t.column("object", .text).notNull()
            t.column("payload_hash", .text).notNull()
            t.column("result", .text).notNull()
            t.column("timestamp", .datetime).notNull()
        }
    }

    // MARK: - Sync, deletion, retrieval (minimal — see file header)

    private static func createForwardLookingTables(_ db: Database) throws {
        try db.create(table: "sync_state") { t in
            t.primaryKey("zone_id", .text)
            t.column("change_token", .blob)
            t.column("last_synced_at", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }

        try db.create(table: "tombstone") { t in
            t.primaryKey("tombstone_id", .text)
            t.column("entity_kind", .text).notNull()
            t.column("entity_id", .text).notNull()
            t.column("deleted_at", .datetime).notNull()
            t.column("purge_state", .text).notNull().defaults(to: "pending")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
            t.uniqueKey(["entity_kind", "entity_id"])
        }

        // Local vector index (docs/01 §2). `vector` is a raw float BLOB
        // pending NSP-089's choice of on-disk vector representation.
        try db.create(table: "embedding") { t in
            t.primaryKey("embedding_id", .text)
            t.column("meeting_id", .text).notNull().references("meeting", onDelete: .cascade)
            t.column("turn_ids_json", .text)
            t.column("sample_start", .integer)
            t.column("sample_end", .integer)
            t.column("chunk_text", .text)
            t.column("model_identifier", .text).notNull()
            t.column("vector", .blob).notNull()
            t.column("excluded_from_memory", .boolean).notNull().defaults(to: false)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("row_revision", .integer).notNull().defaults(to: 1)
        }
    }

    // MARK: - Full-text search

    /// Shells only — NSP-043 owns the maintenance triggers that populate
    /// these and exclude `excluded_from_memory`/`deleted_at` rows (docs/02
    /// §5: "FT triggers exclude... by trigger, not by query-time filtering").
    private static func createFTS5Tables(_ db: Database) throws {
        try db.create(virtualTable: "fts_transcript", using: FTS5()) { t in
            t.tokenizer = .unicode61()
            t.column("turn_id").notIndexed()
            t.column("meeting_id").notIndexed()
            t.column("body")
        }
        try db.create(virtualTable: "fts_notes", using: FTS5()) { t in
            t.tokenizer = .unicode61()
            t.column("block_id").notIndexed()
            t.column("meeting_id").notIndexed()
            t.column("body")
        }
        try db.create(virtualTable: "fts_insight", using: FTS5()) { t in
            t.tokenizer = .unicode61()
            t.column("insight_id").notIndexed()
            t.column("meeting_id").notIndexed()
            t.column("body")
        }
    }
}
// swiftlint:enable type_body_length function_body_length
