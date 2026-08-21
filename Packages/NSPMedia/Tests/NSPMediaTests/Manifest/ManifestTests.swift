import Foundation
import NSPCore
import Testing

@testable import NSPMedia

@Suite("Manifest.validates")
struct ManifestTests {
    private static func makeManifest(segments: [ManifestSegmentRecord], sealed: Bool, sealedAt: Date?) -> Manifest {
        Manifest(
            owner: .meeting(MeetingID(rawValue: UUID())),
            deviceID: DeviceID(rawValue: UUID()),
            captureMode: .watch,
            audioFormat: Manifest.AudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000),
            createdAt: Date(timeIntervalSince1970: 0),
            sealedAt: sealedAt,
            segments: segments,
            integrity: Manifest.Integrity(sealed: sealed)
        )
    }

    private static func makeSegment(sequence: Int, startSample: Int64, sampleCount: Int64) -> ManifestSegmentRecord {
        ManifestSegmentRecord(
            sequence: sequence, segmentID: SegmentID(rawValue: UUID()),
            file: "segments/\(String(format: "%06d", sequence)).m4a", startSample: startSample,
            sampleCount: sampleCount, sha256: Data(repeating: 0, count: 32), closedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func test_emptyUnsealedManifest_validates() {
        #expect(Self.makeManifest(segments: [], sealed: false, sealedAt: nil).validates())
    }

    @Test func test_sequentialGaplessSegments_validate() {
        let segments = [
            Self.makeSegment(sequence: 0, startSample: 0, sampleCount: 1000),
            Self.makeSegment(sequence: 1, startSample: 1000, sampleCount: 500),
            Self.makeSegment(sequence: 2, startSample: 1500, sampleCount: 750),
        ]
        #expect(Self.makeManifest(segments: segments, sealed: false, sealedAt: nil).validates())
    }

    @Test func test_outOfOrderSequence_failsValidation() {
        let segments = [
            Self.makeSegment(sequence: 1, startSample: 0, sampleCount: 1000),
            Self.makeSegment(sequence: 0, startSample: 1000, sampleCount: 500),
        ]
        #expect(!Self.makeManifest(segments: segments, sealed: false, sealedAt: nil).validates())
    }

    @Test func test_gapBetweenSegments_failsValidation() {
        let segments = [
            Self.makeSegment(sequence: 0, startSample: 0, sampleCount: 1000),
            Self.makeSegment(sequence: 1, startSample: 1500, sampleCount: 500),  // should start at 1000
        ]
        #expect(!Self.makeManifest(segments: segments, sealed: false, sealedAt: nil).validates())
    }

    @Test func test_sealedWithoutSealedAt_failsValidation() {
        #expect(!Self.makeManifest(segments: [], sealed: true, sealedAt: nil).validates())
    }

    @Test func test_sealedWithSealedAt_validates() {
        #expect(Self.makeManifest(segments: [], sealed: true, sealedAt: Date()).validates())
    }
}
