import AVFoundation
import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPMedia

/// Real, tiny AAC `.m4a` source fixtures written via the actual
/// `AVAudioFileSegmentEncoder` — `AudioFileImporter` really decodes through
/// `AVFoundation`, so a fake encoder producing a non-container byte stream
/// (`SegmenterTests.FakeSegmentAudioEncoder`) can't stand in as the *source*
/// file here, only the reasoning for using a real one differs from that
/// file's own comment.
@Suite("AudioFileImporter")
struct AudioFileImporterTests {
    private static let sourceFormat = SegmentAudioFormat(codec: .aacLC, sampleRate: 48000, channels: 1, bitRate: 64000)

    private final class FixtureClock: Clock, @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(startingAt date: Date) { self.current = date }
        func now() -> Date { lock.withLock { current } }
    }

    private static func writeSourceFixture(at url: URL, durationSeconds: Double = 0.5) throws -> Int {
        let sampleCount = Int(durationSeconds * Double(sourceFormat.sampleRate))
        var samples = [Float](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let t = Double(index) / Double(sourceFormat.sampleRate)
            samples[index] = Float(sin(2 * Double.pi * 440 * t)) * 0.5
        }
        let encoder = AVAudioFileSegmentEncoder()
        try encoder.startSegment(at: url, format: sourceFormat)
        try encoder.append(samples)
        try encoder.finishWriting()
        return sampleCount
    }

    private static func makeMeetingGraph(_ appDatabase: AppDatabase, meetingID: MeetingID) async throws {
        let meetingIDString = meetingID.rawValue.uuidString
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES ('w1', 'Workspace', '2026-01-01', '2026-01-01', 1)")
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES ('p1', 'w1', 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """)
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, 'w1', 'Test meeting', 0, 'import', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'processing', 'p1', 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """, arguments: [meetingIDString])
        }
    }

    @Test("importFile produces a sealed manifest and a durable, checksummed segment")
    func test_importFile_producesASealedManifestAndSegment() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID())
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)
        let deviceID = DeviceID(rawValue: UUID())

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileImporterTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        let sourceURL = root.appendingPathComponent("source.m4a")
        let sourceSampleCount = try Self.writeSourceFixture(at: sourceURL)

        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let segmentRepository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let importer = AudioFileImporter(
            audioEncoder: AVAudioFileSegmentEncoder(), segmentFileSystem: LiveSegmentFileSystem(),
            segmentRepository: segmentRepository,
            clock: FixtureClock(startingAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let manifest = try await importer.importFile(
            at: sourceURL, meetingID: meetingID, deviceID: deviceID, container: container,
            manifestWriter: manifestWriter, targetFormat: Self.sourceFormat)

        #expect(manifest.validates())
        #expect(manifest.integrity.sealed)
        #expect(manifest.segments.count == 1)

        let record = try #require(manifest.segments.first)
        // AAC's encoder priming/frame padding means the round-tripped
        // sample count is close to, not byte-identical to, the source —
        // a few hundred samples of tolerance covers that without pinning
        // an exact codec-internal constant.
        #expect(abs(record.sampleCount - Int64(sourceSampleCount)) < 2000)
        #expect(!record.sha256.isEmpty)

        let finalURL = container.segmentURL(sequence: 0)
        #expect(FileManager.default.fileExists(atPath: finalURL.path))

        let persisted = try await segmentRepository.fetchAll(owner: .meeting(meetingID))
        #expect(persisted.count == 1)
        #expect(persisted.first?.sha256 == record.sha256)
    }

    @Test("importFile rejects an empty source file")
    func test_importFile_emptySource_throws() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID())
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileImporterTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        let sourceURL = root.appendingPathComponent("empty.m4a")
        _ = try Self.writeSourceFixture(at: sourceURL, durationSeconds: 0)

        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let importer = AudioFileImporter(
            audioEncoder: AVAudioFileSegmentEncoder(), segmentFileSystem: LiveSegmentFileSystem(),
            segmentRepository: GRDBSegmentRepository(dbWriter: appDatabase.dbWriter),
            clock: FixtureClock(startingAt: Date(timeIntervalSince1970: 1_700_000_000)))

        await #expect(throws: Error.self) {
            try await importer.importFile(
                at: sourceURL, meetingID: meetingID, deviceID: DeviceID(rawValue: UUID()), container: container,
                manifestWriter: manifestWriter, targetFormat: Self.sourceFormat)
        }
    }
}
