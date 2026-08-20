import Foundation
import NSPCore
import NSPPersistence

/// In-memory `ActionRepository` so tests never touch a real database
/// (docs/11 §4, NSP-048/NSP-049).
public actor FakeActionRepository: ActionRepository {
    private var storage: [ActionID: Action] = [:]

    public init() {}

    public func insert(_ action: Action, at date: Date) async throws {
        storage[action.actionID] = action
    }

    public func update(_ action: Action, at date: Date) async throws {
        guard storage[action.actionID] != nil else {
            throw PersistenceError.notFound(table: "action_item", key: action.actionID.description)
        }
        storage[action.actionID] = action
    }

    public func find(_ id: ActionID) async throws -> Action? {
        storage[id]
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Action] {
        storage.values.filter { $0.meetingID == meetingID }
    }

    /// `Action` carries only a `meetingID`, so this fake — unlike
    /// `FakeMeetingRepository`, which stores `workspaceID` on the meeting
    /// itself — has no join to filter with and returns everything
    /// unscoped. Fine for single-workspace test fixtures (the only kind
    /// this codebase builds today); a test that needs real workspace
    /// isolation should use `GRDBActionRepository` against a real
    /// `AppDatabase` instead, the same as `GRDBActionRepositoryTests`
    /// does for its own join test.
    public func fetchAll(workspaceID: WorkspaceID) async throws -> [Action] {
        Array(storage.values)
    }

    public func delete(_ id: ActionID) async throws {
        storage.removeValue(forKey: id)
    }
}
