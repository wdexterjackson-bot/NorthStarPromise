import AVFoundation
import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPMedia

/// Real, tiny AAC `.m4a` fixtures written via the actual
/// `AVAudioFileSegmentEncoder` — needed because `SegmentStitcher` really
/// concatenates and exports through `AVFoundation`, not a fake. This can't
/// reuse `NSPTestSupport`'s `GoldenToneBurstGenerator`/`GoldenSegmentFileWriter`
/// — that package depends on `NSPMedia`, so importing it back here would be
/// circular (same reasoning `TimelineReconcilerTests` documents for its own
/// golden-audio test, deferred to `NSPTestSupportTests` instead). The
/// cross-package, known-content round trip lives there
/// (`SegmentStitcherGoldenAudioTests`); this file covers the pure
/// build/cache/validation logic with minimal local audio.
@Suite("SegmentStitcher")
struct SegmentStitcherTests {
    private static let format = SegmentAudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000)

    private static func writeFixtureSegmentFile(
        at url: URL, format: SegmentAudioFormat = format, durationSeconds: Double = 0.3, frequencyHz: Double = 440
    ) throws {
        let sampleCount = Int(durationSeconds * Double(format.sampleRate))
        var samples = [Float](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let t = Double(index) / Double(format.sampleRate)
            samples[index] = Float(sin(2 * Double.pi * frequencyHz * t)) * 0.5
        }
        let encoder = AVAudioFileSegmentEncoder()
        try encoder.startSegment(at: url, format: format)
        try encoder.append(samples)
        try encoder.finishWriting()
    }

    private static func duration(ofFileAt url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    private struct Fixture {
        let container: MeetingContainer
        let meetingID: MeetingID
        let deviceID: DeviceID
    }

    private static func makeFixture() -> Fixture {
        let meetingID = MeetingID(rawValue: UUID())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SegmentStitcherTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        return Fixture(container: container, meetingID: meetingID, deviceID: DeviceID(rawValue: UUID()))
    }

    /// Writes a real fixture file for `segment` at its expected location and
    /// returns `segment` with `localURL`/`sha256` filled in from that real
    /// file — the shape every segment has by the time it's sealed in
    /// production (docs/03 §3.2's atomic close protocol).
    private static func sealedSegment(
        _ segment: Segment, in container: MeetingContainer, durationSeconds: Double = 0.3
    ) throws -> Segment {
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())
        let url = container.segmentURL(sequence: segment.sequence)
        try writeFixtureSegmentFile(at: url, durationSeconds: durationSeconds)
        var sealed = segment
        sealed.localURL = url
        sealed.sha256 = try LiveSegmentFileSystem().sha256(ofFileAt: url)
        return sealed
    }

    private static func makeSegment(
        fixture: Fixture, sequence: Int, startSample: Int64, deviceID: DeviceID? = nil
    ) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()), owner: .meeting(fixture.meetingID),
            deviceID: deviceID ?? fixture.deviceID, sequence: sequence, codec: format.codec,
            sampleRate: format.sampleRate, channels: format.channels, bitRate: format.bitRate,
            startSample: startSample, sampleCount: Int64(0.3 * Double(format.sampleRate)))
    }

    @Test func test_buildOrReuseComposite_concatenatesTwoSegments_durationMatchesSum() async throws {
        let fixture = Self.makeFixture()
        let first = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 0, startSample: 0), in: fixture.container)
        let second = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 1, startSample: first.sampleCount), in: fixture.container)

        let stitcher = SegmentStitcher()
        let compositeURL = try await stitcher.buildOrReuseComposite(
            segments: [first, second], container: fixture.container)

        let compositeDuration = try await Self.duration(ofFileAt: compositeURL)
        #expect(abs(compositeDuration - 0.6) < 0.1)
    }

    @Test func test_buildOrReuseComposite_secondCallWithSameSegments_reusesCache() async throws {
        let fixture = Self.makeFixture()
        let segment = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 0, startSample: 0), in: fixture.container)
        let stitcher = SegmentStitcher()

        let firstURL = try await stitcher.buildOrReuseComposite(segments: [segment], container: fixture.container)
        let firstModified = try FileManager.default.attributesOfItem(atPath: firstURL.path)[.modificationDate] as? Date

        let secondURL = try await stitcher.buildOrReuseComposite(segments: [segment], container: fixture.container)
        let secondModified =
            try FileManager.default.attributesOfItem(atPath: secondURL.path)[.modificationDate] as? Date

        #expect(firstURL == secondURL)
        #expect(firstModified == secondModified)
    }

    @Test func test_buildOrReuseComposite_segmentSetChanges_rebuilds() async throws {
        let fixture = Self.makeFixture()
        let first = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 0, startSample: 0), in: fixture.container)
        let stitcher = SegmentStitcher()
        let firstBuildURL = try await stitcher.buildOrReuseComposite(segments: [first], container: fixture.container)
        let firstDuration = try await Self.duration(ofFileAt: firstBuildURL)

        let second = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 1, startSample: first.sampleCount), in: fixture.container)
        let secondBuildURL = try await stitcher.buildOrReuseComposite(
            segments: [first, second], container: fixture.container)
        let secondDuration = try await Self.duration(ofFileAt: secondBuildURL)

        #expect(secondDuration > firstDuration)
    }

    @Test func test_buildOrReuseComposite_mixedDeviceIDs_throwsMixedDevicesOrFormats() async throws {
        let fixture = Self.makeFixture()
        let first = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 0, startSample: 0), in: fixture.container)
        let otherDeviceSegment = Self.makeSegment(
            fixture: fixture, sequence: 1, startSample: first.sampleCount, deviceID: DeviceID(rawValue: UUID()))
        let second = try Self.sealedSegment(otherDeviceSegment, in: fixture.container)

        await #expect(throws: SegmentStitcherError.mixedDevicesOrFormats) {
            try await SegmentStitcher().buildOrReuseComposite(segments: [first, second], container: fixture.container)
        }
    }

    @Test func test_buildOrReuseComposite_segmentWithoutLocalURL_throwsSegmentUnavailableLocally() async throws {
        let fixture = Self.makeFixture()
        var segment = try Self.sealedSegment(
            Self.makeSegment(fixture: fixture, sequence: 0, startSample: 0), in: fixture.container)
        segment.localURL = nil

        await #expect(throws: SegmentStitcherError.segmentUnavailableLocally(segment.segmentID)) {
            try await SegmentStitcher().buildOrReuseComposite(segments: [segment], container: fixture.container)
        }
    }

    @Test func test_buildOrReuseComposite_emptySegments_throwsNoSegments() async throws {
        let fixture = Self.makeFixture()
        await #expect(throws: SegmentStitcherError.noSegments) {
            try await SegmentStitcher().buildOrReuseComposite(segments: [], container: fixture.container)
        }
    }
}
