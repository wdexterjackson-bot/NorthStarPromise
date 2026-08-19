import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPTestSupport

@Suite("Fake repositories")
struct FakeRepositoriesTests {
    @Test func test_fakeMeetingRepository_insertFindUpdate() async throws {
        let repository = FakeMeetingRepository()
        let meeting = MeetingFixtureBuilder(clock: FakeClock()).build()

        try await repository.insert(meeting, at: meeting.createdAt)
        #expect(try await repository.find(meeting.meetingID) == meeting)

        var updated = meeting
        updated.title = "Renamed"
        try await repository.update(updated, at: Date())
        #expect(try await repository.find(meeting.meetingID)?.title == "Renamed")
    }

    @Test func test_fakeMeetingRepository_updateMissingRow_throws() async throws {
        let repository = FakeMeetingRepository()
        let meeting = MeetingFixtureBuilder(clock: FakeClock()).build()

        await #expect(throws: PersistenceError.self) {
            try await repository.update(meeting, at: Date())
        }
    }

    @Test func test_fakeSegmentRepository_fetchAllOrdersBySequence() async throws {
        let repository = FakeSegmentRepository()
        let meetingID = MeetingID(rawValue: UUID())
        for sequence in [2, 0, 1] {
            let segment = Segment(
                segmentID: SegmentID(rawValue: UUID()), meetingID: meetingID, deviceID: DeviceID(rawValue: UUID()),
                sequence: sequence, codec: .aacLC, sampleRate: 16_000, channels: 1, bitRate: 32_000,
                startSample: 0, sampleCount: 720_000)
            try await repository.insert(segment, at: Date())
        }

        let all = try await repository.fetchAll(meetingID: meetingID)
        #expect(all.map(\.sequence) == [0, 1, 2])
    }

    @Test func test_fakeTimelineEventRepository_appendAndFetchOrdersBySampleOffset() async throws {
        let repository = FakeTimelineEventRepository()
        let meetingID = MeetingID(rawValue: UUID())
        let later = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), meetingID: meetingID, deviceID: DeviceID(rawValue: UUID()),
            type: .stop, sampleOffset: 5_000, wallClock: Date())
        let earlier = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), meetingID: meetingID, deviceID: DeviceID(rawValue: UUID()),
            type: .start, sampleOffset: 0, wallClock: Date())

        try await repository.append(later, at: Date())
        try await repository.append(earlier, at: Date())

        let all = try await repository.fetchAll(meetingID: meetingID)
        #expect(all.map(\.eventID) == [earlier.eventID, later.eventID])
    }
}
