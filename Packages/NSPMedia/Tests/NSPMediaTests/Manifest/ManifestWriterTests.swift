import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPMedia

@Suite("ManifestWriter")
struct ManifestWriterTests {
    /// A fresh, real temp directory per test — `LiveManifestFileSystem`
    /// needs genuine fsync/rename semantics, which no in-memory fake can
    /// stand in for here (NSP-014).
    private static func makeContainer() -> MeetingContainer {
        let containerRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestWriterTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: containerRoot, meetingID: MeetingID(rawValue: UUID()))
        try? FileManager.default.createDirectory(at: container.rootURL, withIntermediateDirectories: true)
        return container
    }

    private static func makeManifest(meetingID: MeetingID, deviceID: DeviceID) -> Manifest {
        Manifest(
            owner: .meeting(meetingID), deviceID: deviceID, captureMode: .watch,
            audioFormat: Manifest.AudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000),
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeSegmentEntry(sequence: Int) -> ManifestWALEntry {
        .segment(
            ManifestSegmentRecord(
                sequence: sequence, segmentID: SegmentID(rawValue: UUID()),
                file: "segments/\(String(format: "%06d", sequence)).m4a", startSample: Int64(sequence * 1000),
                sampleCount: 1000, sha256: Data(repeating: UInt8(sequence), count: 32),
                closedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test func test_append_isReplayedInOrder() async throws {
        let container = Self.makeContainer()
        let writer = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())

        try await writer.append(Self.makeSegmentEntry(sequence: 0))
        try await writer.append(Self.makeSegmentEntry(sequence: 1))
        try await writer.append(Self.makeSegmentEntry(sequence: 2))

        let entries = try await writer.replayWAL()
        #expect(entries.count == 3)
        guard case .segment(let first) = entries[0], case .segment(let second) = entries[1],
            case .segment(let third) = entries[2]
        else {
            Issue.record("expected three .segment entries")
            return
        }
        let sequences: [Int] = [first.sequence, second.sequence, third.sequence]
        #expect(sequences == [0, 1, 2])
    }

    @Test func test_seal_writesAValidatingSealedManifestAndTruncatesTheWAL() async throws {
        let container = Self.makeContainer()
        let writer = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())

        try await writer.append(Self.makeSegmentEntry(sequence: 0))
        try await writer.seal(Self.makeManifest(meetingID: meetingID, deviceID: deviceID), sealedAt: Date())

        let loaded = try await writer.loadCurrentManifest()
        #expect(loaded?.integrity.sealed == true)
        #expect(loaded?.sealedAt != nil)
        #expect(loaded?.validates() == true)

        let remainingWAL = try await writer.replayWAL()
        #expect(remainingWAL.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: container.manifestBackupURL.path))
    }

    @Test func test_secondSeal_rotatesThePreviousManifestIntoBak() async throws {
        let container = Self.makeContainer()
        let writer = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())

        var first = Self.makeManifest(meetingID: meetingID, deviceID: deviceID)
        first.segments = [
            ManifestSegmentRecord(
                sequence: 0, segmentID: SegmentID(rawValue: UUID()), file: "segments/000000.m4a", startSample: 0,
                sampleCount: 1000, sha256: Data(repeating: 0, count: 32), closedAt: Date(timeIntervalSince1970: 0))
        ]
        try await writer.seal(first, sealedAt: Date(timeIntervalSince1970: 100))

        var second = first
        second.segments.append(
            ManifestSegmentRecord(
                sequence: 1, segmentID: SegmentID(rawValue: UUID()), file: "segments/000001.m4a", startSample: 1000,
                sampleCount: 500, sha256: Data(repeating: 1, count: 32), closedAt: Date(timeIntervalSince1970: 200)))
        try await writer.seal(second, sealedAt: Date(timeIntervalSince1970: 200))

        #expect(FileManager.default.fileExists(atPath: container.manifestBackupURL.path))
        let current = try await writer.loadCurrentManifest()
        #expect(current?.segments.count == 2)
    }

    @Test func test_replayWAL_dropsATruncatedTrailingLine() async throws {
        let container = Self.makeContainer()
        let fileSystem = LiveManifestFileSystem()
        let writer = ManifestWriter(container: container, fileSystem: fileSystem)

        try await writer.append(Self.makeSegmentEntry(sequence: 0))
        // Simulate a crash mid-append: a partial, non-JSON trailing line.
        try fileSystem.appendAndFsync(Data("{\"incomplete".utf8), to: container.manifestWALURL)

        let entries = try await writer.replayWAL()
        #expect(entries.count == 1)
    }

    @Test func test_loadCurrentManifest_fallsBackToBakWhenPrimaryIsMissing() async throws {
        let container = Self.makeContainer()
        let writer = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())

        try await writer.seal(Self.makeManifest(meetingID: meetingID, deviceID: deviceID), sealedAt: Date())
        // A second seal rotates the first into .bak.
        try await writer.seal(Self.makeManifest(meetingID: meetingID, deviceID: deviceID), sealedAt: Date())
        // Simulate the primary being lost/corrupted after the fact.
        try FileManager.default.removeItem(at: container.manifestURL)

        let recovered = try await writer.loadCurrentManifest()
        #expect(recovered != nil)
        #expect(recovered?.validates() == true)
    }
}
