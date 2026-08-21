import Foundation
import Testing

@testable import NSPCore

@Suite("ScheduledRecordingScheduling")
struct ScheduledRecordingSchedulingTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let stop = start.addingTimeInterval(3600)

    private static func item(
        status: ScheduledRecordingStatus, start: Date = ScheduledRecordingSchedulingTests.start,
        stop: Date = ScheduledRecordingSchedulingTests.stop, notifyLeadTime: TimeInterval = 0
    ) -> ScheduledRecording {
        ScheduledRecording(
            scheduledRecordingID: .generate(clock: SystemClock()), workspaceID: .generate(clock: SystemClock()),
            title: "Test", scheduledStart: start, scheduledStop: stop, status: status, notifyLeadTime: notifyLeadTime,
            createdAt: start.addingTimeInterval(-60), updatedAt: start.addingTimeInterval(-60))
    }

    @Test func test_pending_beforeNotifyPoint_isNotYetDue() {
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .pending, notifyLeadTime: 60), at: Self.start.addingTimeInterval(-120))
        #expect(decision == .notYetDue)
    }

    @Test func test_pending_atExactNotifyPoint_shouldNotify() {
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .pending, notifyLeadTime: 60), at: Self.start.addingTimeInterval(-60))
        #expect(decision == .shouldNotify)
    }

    @Test func test_pending_pastNotifyPoint_shouldNotify() {
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .pending, notifyLeadTime: 60), at: Self.start)
        #expect(decision == .shouldNotify)
    }

    @Test func test_notified_afterStartButBeforeStop_isNotYetDue() {
        // Already notified — waiting on a Start/Skip tap, not a second
        // notification.
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .notified), at: Self.start.addingTimeInterval(600))
        #expect(decision == .notYetDue)
    }

    @Test func test_pendingOrNotified_pastScheduledStop_shouldMarkMissed() {
        for status: ScheduledRecordingStatus in [.pending, .notified] {
            let decision = ScheduledRecordingScheduling.decision(
                for: Self.item(status: status), at: Self.stop)
            #expect(decision == .shouldMarkMissed)
        }
    }

    @Test func test_started_beforeScheduledStop_isNotYetDue() {
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .started), at: Self.stop.addingTimeInterval(-1))
        #expect(decision == .notYetDue)
    }

    @Test func test_started_atExactScheduledStop_shouldAutoStop() {
        let decision = ScheduledRecordingScheduling.decision(for: Self.item(status: .started), at: Self.stop)
        #expect(decision == .shouldAutoStop)
    }

    @Test func test_started_pastScheduledStop_shouldAutoStop() {
        let decision = ScheduledRecordingScheduling.decision(
            for: Self.item(status: .started), at: Self.stop.addingTimeInterval(600))
        #expect(decision == .shouldAutoStop)
    }

    @Test func test_terminalStatuses_alwaysTerminal_regardlessOfTime() {
        for status: ScheduledRecordingStatus in [.completed, .skipped, .missed, .cancelled] {
            for now in [Self.start.addingTimeInterval(-1_000_000), Self.stop.addingTimeInterval(1_000_000)] {
                #expect(ScheduledRecordingScheduling.decision(for: Self.item(status: status), at: now) == .terminal)
            }
        }
    }

    @Test func test_zeroNotifyLeadTime_notifiesExactlyAtScheduledStart() {
        let decision = ScheduledRecordingScheduling.decision(for: Self.item(status: .pending), at: Self.start)
        #expect(decision == .shouldNotify)
    }
}
