import Foundation
import GRDB
import Testing

@testable import NSPPersistence

@Suite("Migration001InitialSchema")
struct Migration001Tests {
    /// Independent of `Migration001InitialSchema.down`'s own table list —
    /// this is the point: it catches drift between what `up` creates and
    /// what anything else believes exists.
    static let expectedTables = [
        "workspace", "person", "person_alias", "policy", "policy_blocked_domain", "policy_blocked_location",
        "meeting", "meeting_missing_segment", "consent_record", "consent_record_participant", "workspace_member",
        "segment", "timeline_event",
        "transcript_turn", "transcript_token", "transcript_language_span", "transcript_turn_segment",
        "note_block", "note_operation",
        "insight", "evidence_span", "evidence_span_turn",
        "action_item", "action_dependency", "action_audit_entry",
        "decision", "decision_alternative", "decision_audit_entry",
        "speaker_cluster", "glossary_entry", "glossary_entry_pronunciation_hint",
        "share_grant", "integration_receipt", "integration_retry", "audit_event",
        "sync_state", "tombstone", "embedding",
        "fts_transcript", "fts_notes", "fts_insight",
    ]

    @Test func test_up_createsEveryExpectedTable() throws {
        let appDatabase = try AppDatabase.makeInMemory()

        try appDatabase.dbWriter.read { db in
            for table in Self.expectedTables {
                let exists = try db.tableExists(table)
                #expect(exists, "missing table: \(table)")
            }
        }
    }

    /// NSP-011 acceptance: "migration is reversible." Applies `up`, tears
    /// every table back down with `down`, then applies `up` again and checks
    /// the resulting schema is identical — proving `down` isn't just
    /// present, but actually undoes what `up` did.
    @Test func test_downThenUp_reproducesTheIdenticalTableSet() throws {
        let dbQueue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())

        try dbQueue.write { db in try Migration001InitialSchema.up(db) }
        let afterFirstUp = try dbQueue.read { db in try Self.userTableNames(db) }
        #expect(Set(afterFirstUp) == Set(Self.expectedTables))

        try dbQueue.write { db in try Migration001InitialSchema.down(db) }
        let afterDown = try dbQueue.read { db in try Self.userTableNames(db) }
        #expect(afterDown.isEmpty, "tables left behind after down(): \(afterDown)")

        try dbQueue.write { db in try Migration001InitialSchema.up(db) }
        let afterSecondUp = try dbQueue.read { db in try Self.userTableNames(db) }
        #expect(Set(afterSecondUp) == Set(afterFirstUp))
    }

    @Test func test_evidenceSpanCheckConstraint_rejectsZeroOrMultipleOwners() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try Self.seedMeetingGraph(appDatabase, meetingID: "m1")

        try appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO insight (
                        insight_id, meeting_id, layer, text, claim_kind, confidence,
                        provenance_model_id, provenance_model_version, provenance_prompt_version,
                        provenance_generated_at, provenance_processing_plane,
                        created_at, updated_at, row_revision
                    ) VALUES (
                        'i1', 'm1', 'flashRecap', 'text', 'said', 0.9,
                        'model', '1', '1', '2026-01-01', 'onDevice',
                        '2026-01-01', '2026-01-01', 1
                    )
                    """)
        }

        // Zero owners: rejected.
        #expect(throws: DatabaseError.self) {
            try appDatabase.dbWriter.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO evidence_span (
                            position, meeting_id, sample_start, sample_end, quoted_text, transcript_revision
                        ) VALUES (0, 'm1', 0, 100, 'quote', 1)
                        """)
            }
        }

        // Two owners: rejected.
        #expect(throws: DatabaseError.self) {
            try appDatabase.dbWriter.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO evidence_span (
                            insight_id, action_id, position, meeting_id, sample_start, sample_end,
                            quoted_text, transcript_revision
                        ) VALUES ('i1', 'does-not-matter', 0, 'm1', 0, 100, 'quote', 1)
                        """)
            }
        }

        // Exactly one owner: accepted.
        try appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO evidence_span (
                        insight_id, position, meeting_id, sample_start, sample_end,
                        quoted_text, transcript_revision
                    ) VALUES ('i1', 0, 'm1', 0, 100, 'quote', 1)
                    """)
        }
    }

    @Test func test_meetingAndConsentRecord_circularReferenceRoundTrips() throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try Self.seedMeetingGraph(appDatabase, meetingID: "m1")

        try appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO consent_record (
                        consent_record_id, meeting_id, method, timestamp, created_at, updated_at, row_revision
                    ) VALUES ('c1', 'm1', 'verbalAnnouncement', '2026-01-01', '2026-01-01', '2026-01-01', 1)
                    """)
            try db.execute(sql: "UPDATE meeting SET consent_record_id = 'c1' WHERE meeting_id = 'm1'")
        }

        let consentRecordID = try appDatabase.dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT consent_record_id FROM meeting WHERE meeting_id = 'm1'")
        }
        #expect(consentRecordID == "c1")
    }

    // MARK: - Helpers

    /// Excludes FTS5's own shadow tables (`<name>_data`, `_idx`, `_config`,
    /// `_docsize`, `_content`) — SQLite creates those automatically
    /// alongside each virtual table in `expectedTables`; they aren't
    /// something this migration declares independently.
    private static func userTableNames(_ db: Database) throws -> [String] {
        let names = try String.fetchAll(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type IN ('table', 'view')
                AND name NOT LIKE 'sqlite_%'
                AND name NOT LIKE 'grdb_%'
                """)
        let ftsShadowSuffixes = ["_data", "_idx", "_config", "_docsize", "_content"]
        return names.filter { name in
            !ftsShadowSuffixes.contains(where: name.hasSuffix)
        }
    }

    /// Minimal workspace → policy → meeting graph every other test builds
    /// on, so each test only has to state what it's actually exercising.
    private static func seedMeetingGraph(_ appDatabase: AppDatabase, meetingID: String) throws {
        try appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES ('w1', 'Workspace', '2026-01-01', '2026-01-01', 1)")
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES ('p1', 'w1', 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """)
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        '\(meetingID)', 'w1', 'Test meeting', 0, 'watch', 'watch-1',
                        '2026-01-01', 'ready', 'p1', 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """)
        }
    }
}
