import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `NSPThread`. Renamed and reshaped from the former
/// `ThreadInMotionRepository`, then reshaped again per the user's own
/// correction to `DASHBOARD_SPEC.md` §3.5's original "each meeting joins
/// zero or one thread" rule: a meeting may join several threads at once,
/// via the `meeting_thread` join table (`Migration015AddMeetingThreadBridge`,
/// mirroring `meeting_project`'s exact shape). A thread still never links
/// to `Project`s — the two remain independent categorizations. Protocol-
/// fronted so tests use a fake instead of touching a real database
/// (docs/11 §4).
public protocol NSPThreadRepository: Sendable {
    func insert(_ thread: NSPThread, at date: Date) async throws
    func update(_ thread: NSPThread, at date: Date) async throws
    func find(_ id: NSPThreadID) async throws -> NSPThread?
    func fetchAll(workspaceID: WorkspaceID) async throws -> [NSPThread]
    func delete(_ id: NSPThreadID) async throws

    /// Replaces `meetingID`'s entire thread membership — the meeting-side
    /// edit path (a future Overview-screen thread picker, mirroring
    /// `ProjectRepository.setProjects`).
    func setThreads(for meetingID: MeetingID, threadIDs: Set<NSPThreadID>) async throws
    /// Replaces `threadID`'s entire meeting membership — the thread-side
    /// edit path `ThreadDetailView`'s "Edit Meetings" sheet uses, and what
    /// accepting a `ThreadSuggestionEngine` suggestion calls.
    func setMeetings(for threadID: NSPThreadID, meetingIDs: Set<MeetingID>) async throws
    func fetchThreadIDs(for meetingID: MeetingID) async throws -> Set<NSPThreadID>
    func fetchMeetingIDs(for threadID: NSPThreadID) async throws -> Set<MeetingID>
    /// Every `meeting_thread` link in the workspace, grouped by thread —
    /// `DashboardComposer`'s one bulk read instead of one query per thread.
    func fetchMeetingIDsByThread(workspaceID: WorkspaceID) async throws -> [NSPThreadID: Set<MeetingID>]
}

public struct GRDBNSPThreadRepository: NSPThreadRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ thread: NSPThread, at date: Date) async throws {
        let row = NSPThreadRow(thread: thread, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ thread: NSPThread, at date: Date) async throws {
        let id = thread.threadID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try NSPThreadRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: NSPThreadRow.databaseTableName, key: id)
            }
            let updated = NSPThreadRow(
                thread: thread, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: NSPThreadID) async throws -> NSPThread? {
        try await dbWriter.read { db in
            try NSPThreadRow.fetchOne(db, key: id.rawValue.uuidString)?.asDomain()
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [NSPThread] {
        try await dbWriter.read { db in
            try NSPThreadRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .order(Column("title"))
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }

    public func delete(_ id: NSPThreadID) async throws {
        try await dbWriter.write { db in
            _ = try NSPThreadRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    public func setThreads(for meetingID: MeetingID, threadIDs: Set<NSPThreadID>) async throws {
        let meetingIDString = meetingID.rawValue.uuidString
        try await dbWriter.write { db in
            try MeetingThreadRow.filter(Column("meeting_id") == meetingIDString).deleteAll(db)
            for threadID in threadIDs {
                try MeetingThreadRow(meetingID: meetingIDString, threadID: threadID.rawValue.uuidString).insert(db)
            }
        }
    }

    public func setMeetings(for threadID: NSPThreadID, meetingIDs: Set<MeetingID>) async throws {
        let threadIDString = threadID.rawValue.uuidString
        try await dbWriter.write { db in
            try MeetingThreadRow.filter(Column("thread_id") == threadIDString).deleteAll(db)
            for meetingID in meetingIDs {
                try MeetingThreadRow(meetingID: meetingID.rawValue.uuidString, threadID: threadIDString).insert(db)
            }
        }
    }

    public func fetchThreadIDs(for meetingID: MeetingID) async throws -> Set<NSPThreadID> {
        let meetingIDString = meetingID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingThreadRow.filter(Column("meeting_id") == meetingIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.threadID) }.map { NSPThreadID(rawValue: $0) })
        }
    }

    public func fetchMeetingIDs(for threadID: NSPThreadID) async throws -> Set<MeetingID> {
        let threadIDString = threadID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingThreadRow.filter(Column("thread_id") == threadIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.meetingID) }.map { MeetingID(rawValue: $0) })
        }
    }

    public func fetchMeetingIDsByThread(workspaceID: WorkspaceID) async throws -> [NSPThreadID: Set<MeetingID>] {
        try await dbWriter.read { db in
            let rows = try MeetingThreadRow.fetchAll(
                db,
                sql: """
                    SELECT meeting_thread.* FROM meeting_thread
                    JOIN meeting ON meeting.meeting_id = meeting_thread.meeting_id
                    WHERE meeting.workspace_id = ?
                    """, arguments: [workspaceID.rawValue.uuidString])
            var result: [NSPThreadID: Set<MeetingID>] = [:]
            for row in rows {
                guard let threadUUID = UUID(uuidString: row.threadID), let meetingUUID = UUID(uuidString: row.meetingID)
                else { continue }
                result[NSPThreadID(rawValue: threadUUID), default: []].insert(MeetingID(rawValue: meetingUUID))
            }
            return result
        }
    }
}

/// Mirrors one row of the `meeting_thread` join table
/// (`Migration015AddMeetingThreadBridge`) — same shape as `MeetingProjectRow`.
struct MeetingThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_thread"

    var meetingID: String
    var threadID: String

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case threadID = "thread_id"
    }
}

struct NSPThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "thread"

    var threadID: String
    var workspaceID: String
    var title: String
    var description: String?
    var kind: String
    var colorSlot: Int
    var status: String
    var lastTouchedAt: Date
    var nextMeetingID: String?
    var externalOrgID: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case workspaceID = "workspace_id"
        case title
        case description
        case kind
        case colorSlot = "color_slot"
        case status
        case lastTouchedAt = "last_touched_at"
        case nextMeetingID = "next_meeting_id"
        case externalOrgID = "external_org_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(thread: NSPThread, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.threadID = thread.threadID.rawValue.uuidString
        self.workspaceID = thread.workspaceID.rawValue.uuidString
        self.title = thread.title
        self.description = thread.threadDescription
        self.kind = thread.kind.rawValue
        self.colorSlot = thread.colorSlot
        self.status = thread.status.rawValue
        self.lastTouchedAt = thread.lastTouchedAt
        self.nextMeetingID = thread.nextMeetingID?.rawValue.uuidString
        self.externalOrgID = thread.externalOrgID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> NSPThread {
        guard let threadUUID = UUID(uuidString: threadID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "thread_id", value: threadID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let threadKind = ThreadKind(rawValue: kind) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "kind", value: kind)
        }
        guard let threadStatus = NSPThreadStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }
        let resolvedNextMeetingID: MeetingID? =
            try nextMeetingID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "next_meeting_id", value: $0)
                }
                return MeetingID(rawValue: uuid)
            }
        return NSPThread(
            threadID: NSPThreadID(rawValue: threadUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID),
            title: title, threadDescription: description, kind: threadKind, colorSlot: colorSlot, status: threadStatus,
            lastTouchedAt: lastTouchedAt, nextMeetingID: resolvedNextMeetingID, externalOrgID: externalOrgID,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
