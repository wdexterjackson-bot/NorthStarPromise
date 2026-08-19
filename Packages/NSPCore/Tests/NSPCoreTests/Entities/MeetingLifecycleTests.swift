import Testing

@testable import NSPCore

@Suite("MeetingLifecycle")
struct MeetingLifecycleTests {
    @Test func test_beginRecording_withoutArming_isIllegal() {
        let lifecycle = MeetingLifecycle()  // .ready

        #expect(throws: MeetingLifecycleError.self) {
            try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)
        }
    }

    @Test func test_beginRecording_opensSegmentAndEntersRecording() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)

        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)

        #expect(lifecycle.state == .recording)
        #expect(lifecycle.hasOpenSegment)
    }

    @Test func test_pauseResume_fiveCycles_producesSixOrderedSegments() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)

        for _ in 0..<5 {
            lifecycle = try MeetingLifecycle.transition(
                from: lifecycle, command: .pause(segmentSampleCount: 16000))
            lifecycle = try MeetingLifecycle.transition(
                from: lifecycle, command: .resume(gapSampleCount: 800))
        }
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .finalize(finalSegmentSampleCount: 16000))

        #expect(lifecycle.closedSegments.count == 6)
        #expect(lifecycle.closedSegments.map(\.sequence) == Array(0..<6))
        #expect(lifecycle.recordedSampleCount == 6 * 16000)
        #expect(lifecycle.gapSampleCounts.count == 5)
        #expect(lifecycle.state == .finalizing)
    }

    @Test func test_finalizeFromRecording_withoutClosingOpenSegment_isIllegal() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)

        #expect(throws: MeetingLifecycleError.self) {
            try MeetingLifecycle.transition(from: lifecycle, command: .finalize(finalSegmentSampleCount: nil))
        }
    }

    @Test func test_finalizeFromPaused_withASegmentCount_isIllegal() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .pause(segmentSampleCount: 16000))

        #expect(throws: MeetingLifecycleError.self) {
            try MeetingLifecycle.transition(
                from: lifecycle, command: .finalize(finalSegmentSampleCount: 100))
        }
    }

    @Test func test_interruptThenRecoverable_neverReopensASegment() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle,
            command: .interrupt(cause: .phoneCall, segmentSampleCount: 32000))

        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .resolveInterruptionRecoverable)

        #expect(lifecycle.state == .recoverable)
        #expect(!lifecycle.hasOpenSegment)
        #expect(lifecycle.closedSegments.count == 1)
    }

    @Test func test_fullHappyPath_readyToShared() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .finalize(finalSegmentSampleCount: 480_000))
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginProcessing)
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .completeProcessing(success: true))
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .share)

        #expect(lifecycle.state == .shared)
    }

    @Test func test_processingFailure_reachesPartialFailure() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginRecording)
        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .finalize(finalSegmentSampleCount: 480_000))
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .beginProcessing)

        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .completeProcessing(success: false))

        #expect(lifecycle.state == .partialFailure)
    }

    @Test func test_archivedAndDeleted_bothRestoreAndPurge() throws {
        let archived = MeetingLifecycle(state: .archived)
        let deleted = MeetingLifecycle(state: .deleted)

        #expect(try MeetingLifecycle.transition(from: archived, command: .restore).state == .restored)
        #expect(try MeetingLifecycle.transition(from: archived, command: .purge).state == .purged)
        #expect(try MeetingLifecycle.transition(from: deleted, command: .restore).state == .restored)
        #expect(try MeetingLifecycle.transition(from: deleted, command: .purge).state == .purged)
    }

    @Test func test_armingFail_carriesReason() throws {
        var lifecycle = MeetingLifecycle()
        lifecycle = try MeetingLifecycle.transition(from: lifecycle, command: .arm)

        lifecycle = try MeetingLifecycle.transition(
            from: lifecycle, command: .fail(reason: "microphone permission denied"))

        #expect(lifecycle.state == .failed(reason: "microphone permission denied"))
    }
}
