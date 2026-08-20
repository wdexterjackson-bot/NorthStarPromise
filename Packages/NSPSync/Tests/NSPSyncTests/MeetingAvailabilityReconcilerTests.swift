import Foundation
import NSPCore
import Testing

@testable import NSPSync

@Suite("MeetingAvailabilityReconciler")
struct MeetingAvailabilityReconcilerTests {
    private static func makeSegment(sequence: Int, deviceID: DeviceID, hasLocalAudio: Bool) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()), meetingID: MeetingID(rawValue: UUID()), deviceID: deviceID,
            sequence: sequence, codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000,
            startSample: Int64(sequence) * 1000, sampleCount: 1000,
            localURL: hasLocalAudio ? URL(fileURLWithPath: "/tmp/\(sequence).m4a") : nil)
    }

    @Test func test_noKnownSegments_isComplete() {
        #expect(MeetingAvailabilityReconciler.availability(for: []) == .complete)
    }

    @Test func test_everySegmentHasLocalAudio_isComplete() {
        let deviceID = DeviceID(rawValue: UUID())
        let segments = (0..<3).map { Self.makeSegment(sequence: $0, deviceID: deviceID, hasLocalAudio: true) }

        #expect(MeetingAvailabilityReconciler.availability(for: segments) == .complete)
    }

    @Test func test_oneSegmentMissingAudio_isPartialAndNamesTheHoldingDevice() {
        let deviceA = DeviceID(rawValue: UUID())
        let deviceB = DeviceID(rawValue: UUID())
        let present = Self.makeSegment(sequence: 0, deviceID: deviceA, hasLocalAudio: true)
        let missing = Self.makeSegment(sequence: 1, deviceID: deviceB, hasLocalAudio: false)

        let availability = MeetingAvailabilityReconciler.availability(for: [present, missing])

        guard case .partial(let missingRefs) = availability else {
            Issue.record("expected .partial, got \(availability)")
            return
        }
        #expect(missingRefs.count == 1)
        #expect(missingRefs[0].segmentID == missing.segmentID)
        #expect(missingRefs[0].deviceID == deviceB)
        #expect(missingRefs[0].sequence == 1)
    }

    @Test func test_missingSegments_areListedInSequenceOrder() {
        let deviceID = DeviceID(rawValue: UUID())
        let segments = [
            Self.makeSegment(sequence: 2, deviceID: deviceID, hasLocalAudio: false),
            Self.makeSegment(sequence: 0, deviceID: deviceID, hasLocalAudio: false),
            Self.makeSegment(sequence: 1, deviceID: deviceID, hasLocalAudio: true),
        ]

        let availability = MeetingAvailabilityReconciler.availability(for: segments)

        guard case .partial(let missingRefs) = availability else {
            Issue.record("expected .partial, got \(availability)")
            return
        }
        #expect(missingRefs.map(\.sequence) == [0, 2])
    }
}
