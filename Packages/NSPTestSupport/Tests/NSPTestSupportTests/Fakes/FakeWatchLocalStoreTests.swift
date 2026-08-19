import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPTestSupport

@Suite("FakeWatchLocalStore")
struct FakeWatchLocalStoreTests {
    @Test func test_upsertFindRemove() async throws {
        let store = FakeWatchLocalStore()
        let meetingID = MeetingID(rawValue: UUID())
        let entry = WatchMeetingIndexEntry(
            meetingID: meetingID, createdAt: Date(timeIntervalSince1970: 0), state: .recording,
            captureMode: .watch, segmentCount: 1, updatedAt: Date(timeIntervalSince1970: 1))

        try await store.upsert(entry)
        #expect(try await store.find(meetingID) == entry)
        #expect(try await store.all() == [entry])

        try await store.remove(meetingID)
        #expect(try await store.find(meetingID) == nil)
        #expect(try await store.all().isEmpty)
    }
}
