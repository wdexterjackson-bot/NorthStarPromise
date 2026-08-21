import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD and query paths for `Meeting` (NSP-012). Protocol-fronted so tests
/// use a fake instead of touching a real database (docs/11 §4).
public protocol MeetingRepository: Sendable {
    func insert(_ meeting: Meeting, at date: Date) async throws
    func update(_ meeting: Meeting, at date: Date) async throws
    func find(_ id: MeetingID) async throws -> Meeting?
    func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Meeting]
    /// Every meeting joined to this thread — reads the `meeting_thread`
    /// join table (`Migration015AddMeetingThreadBridge`; a meeting may
    /// join several threads at once).
    func fetchAll(threadID: NSPThreadID) async throws -> [Meeting]
    /// Deletes the meeting row. Every table with a real `meeting_id` foreign
    /// key (`insight`, `action_item`, `decision`, `evidence_span`, ...)
    /// still declares `ON DELETE CASCADE` and cleans up automatically.
    /// `segment`/`transcript_turn`/`note_block` no longer have that FK —
    /// they're polymorphic over `Meeting`/`BrainDump`/`Note` now
    /// (`Migration012AddNotesAndBrainDumps`) — so this explicitly deletes
    /// those three via `OwnedContentCleanup` first. On-disk cleanup (the
    /// audio/ink files themselves) is still the caller's job, not this
    /// repository's (docs/11 §4: repositories own DB rows, not the
    /// filesystem).
    func delete(_ id: MeetingID) async throws
}

public struct GRDBMeetingRepository: MeetingRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ meeting: Meeting, at date: Date) async throws {
        let row = MeetingRow(
            meeting: meeting, createdAt: date, updatedAt: date, rowRevision: 1, cloudRecordChangeTag: nil)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.syncMissingSegments(db, meetingID: row.meetingID, availability: meeting.availability)
        }
    }

    public func update(_ meeting: Meeting, at date: Date) async throws {
        let meetingID = meeting.meetingID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try MeetingRow.fetchOne(db, key: meetingID) else {
                throw PersistenceError.notFound(table: MeetingRow.databaseTableName, key: meetingID)
            }
            let updated = MeetingRow(
                meeting: meeting,
                createdAt: existing.createdAt,
                updatedAt: date,
                rowRevision: existing.rowRevision + 1,
                cloudRecordChangeTag: existing.cloudRecordChangeTag
            )
            try updated.update(db)
            try Self.syncMissingSegments(db, meetingID: meetingID, availability: meeting.availability)
        }
    }

    public func find(_ id: MeetingID) async throws -> Meeting? {
        try await dbWriter.read { db in
            try Self.fetchMeeting(db, meetingID: id.rawValue.uuidString)
        }
    }

    public func delete(_ id: MeetingID) async throws {
        try await dbWriter.write { db in
            try OwnedContentCleanup.deleteAll(for: .meeting(id), in: db)
            _ = try MeetingRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    public func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Meeting] {
        try await dbWriter.read { db in
            var request = MeetingRow.filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
            if !includeDeleted {
                request = request.filter(Column("deleted_at") == nil)
            }
            let rows = try request.order(Column("started_at").desc).fetchAll(db)
            return try rows.map { row in
                try row.asDomain(missingSegments: try Self.fetchMissingSegments(db, meetingID: row.meetingID))
            }
        }
    }

    public func fetchAll(threadID: NSPThreadID) async throws -> [Meeting] {
        try await dbWriter.read { db in
            let rows = try MeetingRow.fetchAll(
                db,
                sql: """
                    SELECT meeting.* FROM meeting
                    JOIN meeting_thread ON meeting_thread.meeting_id = meeting.meeting_id
                    WHERE meeting_thread.thread_id = ? AND meeting.deleted_at IS NULL
                    ORDER BY meeting.started_at DESC
                    """, arguments: [threadID.rawValue.uuidString])
            return try rows.map { row in
                try row.asDomain(missingSegments: try Self.fetchMissingSegments(db, meetingID: row.meetingID))
            }
        }
    }

    // MARK: - Helpers

    private static func fetchMeeting(_ db: Database, meetingID: String) throws -> Meeting? {
        guard let row = try MeetingRow.fetchOne(db, key: meetingID) else { return nil }
        return try row.asDomain(missingSegments: try fetchMissingSegments(db, meetingID: meetingID))
    }

    private static func fetchMissingSegments(_ db: Database, meetingID: String) throws -> [SegmentRef] {
        try MeetingMissingSegmentRow
            .filter(Column("meeting_id") == meetingID)
            .fetchAll(db)
            .map { try $0.asDomain() }
    }

    /// Replaces every `meeting_missing_segment` row for this meeting with
    /// the current `Availability.partial(missing:)` list — simplest correct
    /// sync for a list this small (docs/02 §2: missing segments are named
    /// explicitly per `.partial` meeting, never more than a handful).
    private static func syncMissingSegments(
        _ db: Database, meetingID: String, availability: Availability
    ) throws {
        try db.execute(sql: "DELETE FROM meeting_missing_segment WHERE meeting_id = ?", arguments: [meetingID])
        guard case .partial(let missing) = availability else { return }
        for ref in missing {
            try MeetingMissingSegmentRow(meetingID: meetingID, ref: ref).insert(db)
        }
    }
}
