import Foundation
import NSPCore
import NSPPersistence

/// In-memory `MeetingRepository` so tests never touch a real database
/// (docs/11 §4, NSP-012).
public actor FakeMeetingRepository: MeetingRepository {
    private var storage: [MeetingID: Meeting] = [:]
    /// A meeting↔thread join, in-memory — real `Meeting`/`NSPThread`
    /// linkage lives in `meeting_thread` now (`Migration015
    /// AddMeetingThreadBridge`), a table this fake has no GRDB-backed
    /// counterpart for, so it just keeps its own copy. Set directly by
    /// tests via `setThreadIDs(_:for:)`, mirroring what a real
    /// `NSPThreadRepository.setMeetings`/`setThreads` call would produce.
    private var threadLinks: [MeetingID: Set<NSPThreadID>] = [:]

    public init() {}

    public func setThreadIDs(_ threadIDs: Set<NSPThreadID>, for meetingID: MeetingID) {
        threadLinks[meetingID] = threadIDs
    }

    public func insert(_ meeting: Meeting, at date: Date) async throws {
        storage[meeting.meetingID] = meeting
    }

    public func update(_ meeting: Meeting, at date: Date) async throws {
        guard storage[meeting.meetingID] != nil else {
            throw PersistenceError.notFound(table: "meeting", key: meeting.meetingID.description)
        }
        storage[meeting.meetingID] = meeting
    }

    public func find(_ id: MeetingID) async throws -> Meeting? {
        storage[id]
    }

    public func delete(_ id: MeetingID) async throws {
        storage.removeValue(forKey: id)
    }

    public func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Meeting] {
        storage.values
            .filter { $0.workspaceID == workspaceID && (includeDeleted || $0.deletedAt == nil) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func fetchAll(threadID: NSPThreadID) async throws -> [Meeting] {
        storage.values
            .filter { (threadLinks[$0.meetingID] ?? []).contains(threadID) && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
