import Foundation
import NSPCore
import NSPPersistence

/// In-memory `MeetingRepository` so tests never touch a real database
/// (docs/11 §4, NSP-012).
public actor FakeMeetingRepository: MeetingRepository {
    private var storage: [MeetingID: Meeting] = [:]

    public init() {}

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

    public func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Meeting] {
        storage.values
            .filter { $0.workspaceID == workspaceID && (includeDeleted || $0.deletedAt == nil) }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
