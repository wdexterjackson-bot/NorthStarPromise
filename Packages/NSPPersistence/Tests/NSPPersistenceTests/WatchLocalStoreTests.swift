import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("FileBackedWatchLocalStore")
struct WatchLocalStoreTests {
    private static func makeIndexURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("watch-index.json")
    }

    private static func makeEntry(meetingID: MeetingID = MeetingID(rawValue: UUID())) -> WatchMeetingIndexEntry {
        WatchMeetingIndexEntry(
            meetingID: meetingID, createdAt: Date(timeIntervalSince1970: 0), state: .recording,
            captureMode: .watch, segmentCount: 2, updatedAt: Date(timeIntervalSince1970: 100))
    }

    @Test func test_emptyStore_returnsNoEntries() async throws {
        let store = FileBackedWatchLocalStore(indexURL: Self.makeIndexURL(), fileSystem: LiveWatchIndexFileSystem())
        #expect(try await store.all().isEmpty)
    }

    @Test func test_upsert_thenAll_containsTheEntry() async throws {
        let store = FileBackedWatchLocalStore(indexURL: Self.makeIndexURL(), fileSystem: LiveWatchIndexFileSystem())
        let entry = Self.makeEntry()

        try await store.upsert(entry)

        let all = try await store.all()
        #expect(all == [entry])
    }

    @Test func test_upsert_sameMeetingIDTwice_updatesInPlaceRatherThanDuplicating() async throws {
        let store = FileBackedWatchLocalStore(indexURL: Self.makeIndexURL(), fileSystem: LiveWatchIndexFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        try await store.upsert(Self.makeEntry(meetingID: meetingID))

        var updated = Self.makeEntry(meetingID: meetingID)
        updated.state = .finalizing
        updated.segmentCount = 9
        try await store.upsert(updated)

        let all = try await store.all()
        #expect(all.count == 1)
        #expect(all[0].state == .finalizing)
        #expect(all[0].segmentCount == 9)
    }

    @Test func test_remove_deletesTheEntry() async throws {
        let store = FileBackedWatchLocalStore(indexURL: Self.makeIndexURL(), fileSystem: LiveWatchIndexFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        try await store.upsert(Self.makeEntry(meetingID: meetingID))

        try await store.remove(meetingID)

        #expect(try await store.all().isEmpty)
        #expect(try await store.find(meetingID) == nil)
    }

    @Test func test_find_returnsTheMatchingEntryOrNil() async throws {
        let store = FileBackedWatchLocalStore(indexURL: Self.makeIndexURL(), fileSystem: LiveWatchIndexFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        try await store.upsert(Self.makeEntry(meetingID: meetingID))

        #expect(try await store.find(meetingID) != nil)
        #expect(try await store.find(MeetingID(rawValue: UUID())) == nil)
    }

    @Test func test_entries_surviveAFreshStoreInstanceOverTheSameFile() async throws {
        let indexURL = Self.makeIndexURL()
        let meetingID = MeetingID(rawValue: UUID())

        let firstStore = FileBackedWatchLocalStore(indexURL: indexURL, fileSystem: LiveWatchIndexFileSystem())
        try await firstStore.upsert(Self.makeEntry(meetingID: meetingID))

        // A fresh instance — simulating relaunch after app termination — must
        // see what was durably written, not what's still in memory.
        let secondStore = FileBackedWatchLocalStore(indexURL: indexURL, fileSystem: LiveWatchIndexFileSystem())
        let recovered = try await secondStore.find(meetingID)

        #expect(recovered != nil)
        #expect(recovered?.segmentCount == 2)
    }
}
