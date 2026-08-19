import Foundation
import NSPCore
import NSPPersistence

/// In-memory `WatchLocalStore` so Watch UI and view-model tests never touch
/// the real filesystem (docs/11 §4, NSP-027).
public actor FakeWatchLocalStore: WatchLocalStore {
    private var storage: [MeetingID: WatchMeetingIndexEntry] = [:]

    public init() {}

    public func upsert(_ entry: WatchMeetingIndexEntry) async throws {
        storage[entry.meetingID] = entry
    }

    public func remove(_ meetingID: MeetingID) async throws {
        storage[meetingID] = nil
    }

    public func all() async throws -> [WatchMeetingIndexEntry] {
        Array(storage.values)
    }

    public func find(_ meetingID: MeetingID) async throws -> WatchMeetingIndexEntry? {
        storage[meetingID]
    }
}
