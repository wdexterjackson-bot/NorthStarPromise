import Foundation
import NSPCore
import Testing

@testable import NSPMedia

@Suite("TimelineReconciler")
struct TimelineReconcilerTests {
    private static func makeSegment(meetingID: MeetingID, sampleCount: Int64) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()), owner: .meeting(meetingID), deviceID: DeviceID(rawValue: UUID()),
            sequence: 0, codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000, startSample: 0,
            sampleCount: sampleCount)
    }

    private static func makeGapEvent(meetingID: MeetingID, gapSamples: Int64) -> TimelineEvent {
        TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            type: .resume, sampleOffset: 0, wallClock: Date(timeIntervalSince1970: 0),
            payload: .object(["gapSamples": .number(Double(gapSamples))]))
    }

    // MARK: - canonicalSampleCount

    @Test func test_canonicalSampleCount_noSegmentsNoGaps_isZero() {
        #expect(TimelineReconciler.canonicalSampleCount(segments: [], gapClosingEvents: []) == 0)
    }

    @Test func test_canonicalSampleCount_sumsSegmentsAndGaps() {
        let meetingID = MeetingID(rawValue: UUID())
        let segments = [
            Self.makeSegment(meetingID: meetingID, sampleCount: 1000),
            Self.makeSegment(meetingID: meetingID, sampleCount: 2000),
        ]
        let gaps = [
            Self.makeGapEvent(meetingID: meetingID, gapSamples: 500),
            Self.makeGapEvent(meetingID: meetingID, gapSamples: 250),
        ]

        let total = TimelineReconciler.canonicalSampleCount(segments: segments, gapClosingEvents: gaps)

        #expect(total == 3750)
    }

    @Test func test_canonicalSampleCount_ignoresEventsWithoutAGapSamplesPayload() {
        let meetingID = MeetingID(rawValue: UUID())
        let segments = [Self.makeSegment(meetingID: meetingID, sampleCount: 1000)]
        let unrelatedEvent = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            type: .marker(kind: .important), sampleOffset: 0, wallClock: Date(timeIntervalSince1970: 0), payload: nil)

        let total = TimelineReconciler.canonicalSampleCount(segments: segments, gapClosingEvents: [unrelatedEvent])

        #expect(total == 1000)
    }

    // MARK: - deviceOffset (wall-clock only)

    @Test func test_deviceOffset_withNoAudio_usesWallClockEstimateAndMarksAnchorEstimated() {
        let origin = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()), sampleZeroWallClock: Date(timeIntervalSince1970: 1000),
            sampleRate: 16000)
        let other = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()), sampleZeroWallClock: Date(timeIntervalSince1970: 1002),
            sampleRate: 16000)

        let offset = TimelineReconciler.deviceOffset(for: other, relativeToOrigin: origin)

        #expect(offset.canonicalSampleOffset == 32000)  // 2s * 16000 Hz
        #expect(offset.anchorEstimated == true)
    }

    // MARK: - deviceOffset (cross-correlation refinement)
    //
    // TC-CAP-006's golden-tone drift test lives in NSPTestSupportTests
    // (`TimelineReconcilerGoldenAudioTests`), not here — it needs
    // `GoldenToneBurstGenerator`, which depends on this module, so it can't
    // be imported back into `NSPMediaTests` (same reasoning as NSP-014's
    // kill-injection test).

    @Test func test_deviceOffset_withSilentUncorrelatedAudio_fallsBackToWallClockEstimate() {
        let sampleRate = 16000
        let silence = [Float](repeating: 0, count: 5000)

        let origin = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()), sampleZeroWallClock: Date(timeIntervalSince1970: 0),
            sampleRate: sampleRate)
        let other = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()), sampleZeroWallClock: Date(timeIntervalSince1970: 1),
            sampleRate: sampleRate)

        let offset = TimelineReconciler.deviceOffset(
            for: other, relativeToOrigin: origin, originAudio: silence, deviceAudio: silence,
            correlationWindowSamples: silence.count, searchRadiusSamples: 100, confidenceFloor: 0.9)

        // Zero-energy audio can never clear a >0 confidence floor — the
        // wall-clock estimate must stand, explicitly marked as such.
        #expect(offset.anchorEstimated == true)
        #expect(offset.canonicalSampleOffset == Int64(sampleRate))
    }
}
