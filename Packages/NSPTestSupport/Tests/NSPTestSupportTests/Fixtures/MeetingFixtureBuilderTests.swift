import Testing

import NSPCore

@testable import NSPTestSupport

@Suite("MeetingFixtureBuilder")
struct MeetingFixtureBuilderTests {
    @Test func test_build_producesAMeetingWithSensibleDefaults() {
        let meeting = MeetingFixtureBuilder().build()

        #expect(meeting.title == "Weekly sync")
        #expect(meeting.captureMode == .watch)
        #expect(meeting.processingMode == .localOnly)
        #expect(meeting.lifecycleState == .readyForReview)
    }

    @Test func test_withOverrides_areReflectedInTheBuiltMeeting() {
        let meeting = MeetingFixtureBuilder()
            .withTitle("1:1 with Sam")
            .withCaptureMode(.phone)
            .withLifecycleState(.recording)
            .withProcessingMode(.cloudAllowed)
            .withAvailability(.recoverable)
            .build()

        #expect(meeting.title == "1:1 with Sam")
        #expect(meeting.captureMode == .phone)
        #expect(meeting.lifecycleState == .recording)
        #expect(meeting.processingMode == .cloudAllowed)
        #expect(meeting.availability == .recoverable)
    }

    @Test func test_build_endedAt_isAfterStartedAt() {
        let meeting = MeetingFixtureBuilder().build()

        #expect(meeting.endedAt! > meeting.startedAt)
    }

    @Test func test_sharedClock_producesTimeOrderedIDsAcrossBuilders() {
        let clock = FakeClock()
        let first = MeetingFixtureBuilder(clock: clock).build()
        clock.advance(by: 1)
        let second = MeetingFixtureBuilder(clock: clock).build()

        #expect(first.meetingID.rawValue.uuidString < second.meetingID.rawValue.uuidString)
    }
}
