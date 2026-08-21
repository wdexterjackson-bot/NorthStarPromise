import GRDB

/// Extends `Migration012AddNotesAndBrainDumps`'s polymorphic-owner change to
/// `timeline_event` — missed in that migration because the Segmenter's own
/// `Manifest`/`TimelineEvent` coupling to `MeetingID` (not just `Segment`/
/// `TranscriptTurn`/`NoteBlock`'s) only surfaced once Phase B's capture-flow
/// work actually tried to record a `BrainDump`/`Note` through the same
/// pipeline. Same rebuild shape as `Migration012` for the same reason:
/// SQLite can't drop a column's foreign key in place.
enum Migration013AddTimelineEventOwnerKind: SchemaMigration {
    static let identifier = "013_addTimelineEventOwnerKind"

    static func up(_ db: Database) throws {
        try db.create(table: "timeline_event_new") { t in
            t.primaryKey("event_id", .text)
            t.column("meeting_id", .text).notNull()
            t.column("owner_kind", .text).notNull().defaults(to: "meeting")
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
        try db.execute(
            sql: """
                INSERT INTO timeline_event_new (
                    event_id, meeting_id, owner_kind, device_id, type, type_detail_json, sample_offset,
                    wall_clock, payload_json, created_at, updated_at, row_revision
                )
                SELECT
                    event_id, meeting_id, 'meeting', device_id, type, type_detail_json, sample_offset,
                    wall_clock, payload_json, created_at, updated_at, row_revision
                FROM timeline_event
                """)
        try db.drop(table: "timeline_event")
        try db.rename(table: "timeline_event_new", to: "timeline_event")
    }

    /// Reverses the table shape, not the data — same rule
    /// `Migration012AddNotesAndBrainDumps.down(_:)` follows: a row actually
    /// owned by a `BrainDump`/`Note` has no meaning in the pre-migration
    /// schema and is dropped rather than kept as an orphan.
    static func down(_ db: Database) throws {
        try db.create(table: "timeline_event_old") { t in
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
        try db.execute(
            sql: """
                INSERT INTO timeline_event_old
                SELECT
                    event_id, meeting_id, device_id, type, type_detail_json, sample_offset, wall_clock,
                    payload_json, created_at, updated_at, row_revision
                FROM timeline_event WHERE owner_kind = 'meeting'
                """)
        try db.drop(table: "timeline_event")
        try db.rename(table: "timeline_event_old", to: "timeline_event")
    }
}
