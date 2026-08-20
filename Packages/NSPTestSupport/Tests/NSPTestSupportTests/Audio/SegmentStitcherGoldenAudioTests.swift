import AVFoundation
import Foundation
import NSPCore
import NSPMedia
import NSPPersistence
import Testing

@testable import NSPTestSupport

/// The cross-package proof that `NSPMedia.SegmentStitcher` really
/// concatenates real, known-content audio — using `GoldenToneBurstGenerator`/
/// `GoldenSegmentFileWriter`, which depend on `NSPMedia`, so this can't live
/// in `NSPMediaTests` (same reasoning as `TimelineReconcilerGoldenAudioTests`).
/// `SegmentStitcherTests` in `NSPMediaTests` covers the pure build/cache/
/// validation logic with minimal local audio; this file is the one place
/// that proves the real, golden-content round trip.
@Suite("SegmentStitcher — golden audio")
struct SegmentStitcherGoldenAudioTests {
    @Test func test_buildOrReuseComposite_concatenatesGoldenSegments_durationMatchesSum() async throws {
        let format = SegmentAudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000)
        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SegmentStitcherGoldenAudioTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        var startSample: Int64 = 0
        var segments: [Segment] = []
        for sequence in 0..<2 {
            let url = container.segmentURL(sequence: sequence)
            let (sampleCount, _) = try GoldenSegmentFileWriter.write(
                to: url, format: format, burstCount: 2, burstDuration: 0.1, gapDuration: 0.1)
            let sha256 = try LiveSegmentFileSystem().sha256(ofFileAt: url)
            segments.append(
                Segment(
                    segmentID: SegmentID(rawValue: UUID()), meetingID: meetingID, deviceID: deviceID,
                    sequence: sequence, codec: format.codec, sampleRate: format.sampleRate,
                    channels: format.channels, bitRate: format.bitRate, startSample: startSample,
                    sampleCount: Int64(sampleCount), sha256: sha256, localURL: url))
            startSample += Int64(sampleCount)
        }

        let expectedTotalSeconds = segments.reduce(0.0) { $0 + Double($1.sampleCount) / Double(format.sampleRate) }

        let compositeURL = try await SegmentStitcher().buildOrReuseComposite(segments: segments, container: container)
        let compositeSeconds = try await AVURLAsset(url: compositeURL).load(.duration).seconds

        #expect(abs(compositeSeconds - expectedTotalSeconds) < 0.1)
    }
}
