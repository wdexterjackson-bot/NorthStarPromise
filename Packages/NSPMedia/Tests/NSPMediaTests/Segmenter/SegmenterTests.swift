import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPMedia

/// A trivial in-memory-buffered `SegmentAudioEncoder` — writes raw `Float`
/// bytes rather than real AAC, so hashes differ across segments without
/// needing a real encoder. Local to `NSPMediaTests` rather than
/// `NSPTestSupport` since that package depends on `NSPMedia` and can't be
/// imported back (same reasoning as every other circular-dependency fake
/// this session). Internal, not `private`, so `CaptureEngineTests` can
/// reuse it too.
final class FakeSegmentAudioEncoder: SegmentAudioEncoder, @unchecked Sendable {
    private let lock = NSLock()
    private var currentURL: URL?
    private var buffer: [Float] = []

    func startSegment(at url: URL, format: SegmentAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }
        currentURL = url
        buffer = []
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    func append(_ samples: [Float]) throws {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }

    func finishWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let url = currentURL else { return }
        let data = buffer.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url)
        currentURL = nil
        buffer = []
    }
}

@Suite("Segmenter")
struct SegmenterTests {
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
                        ?, 'w1', 'Test meeting', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'recording', 'p1', 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """, arguments: [meetingIDString])
        }
    }

    private struct Fixture {
        let segmenter: Segmenter
        let container: MeetingContainer
        let segmentRepository: GRDBSegmentRepository
        let timelineEventRepository: GRDBTimelineEventRepository
        let clock: FixtureClock
        let meetingID: MeetingID
    }

    private final class FixtureClock: Clock, @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(startingAt date: Date) { self.current = date }
        func now() -> Date { lock.withLock { current } }
        func advance(by interval: TimeInterval) { lock.withLock { current = current.addingTimeInterval(interval) } }
    }

    /// - Parameter rotationSeconds: kept tiny in tests so a handful of
    ///   sample appends can exercise interval rotation without needing
    ///   real-time-scale sample counts.
    private static func makeFixture(rotationSeconds: Double = 1) async throws -> Fixture {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID())
        try await makeMeetingGraph(appDatabase, meetingID: meetingID)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SegmenterTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let segmentRepository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let timelineEventRepository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)
        let clock = FixtureClock(startingAt: Date(timeIntervalSince1970: 1_700_000_000))

        let segmenter = Segmenter(
            container: container, audioEncoder: FakeSegmentAudioEncoder(), segmentFileSystem: LiveSegmentFileSystem(),
            manifestWriter: manifestWriter, segmentRepository: segmentRepository,
            timelineEventRepository: timelineEventRepository, clock: clock, meetingID: meetingID,
            deviceID: DeviceID(rawValue: UUID()),
            audioFormat: SegmentAudioFormat(
                codec: .aacLC, sampleRate: 100, channels: 1, bitRate: 32000), rotationSeconds: rotationSeconds)

        return Fixture(
            segmenter: segmenter, container: container, segmentRepository: segmentRepository,
            timelineEventRepository: timelineEventRepository, clock: clock, meetingID: meetingID)
    }

    @Test func test_beginRecording_opensSegmentZeroAndRecordsStart() async throws {
        let fixture = try await Self.makeFixture()

        try await fixture.segmenter.beginRecording()

        #expect(FileManager.default.fileExists(atPath: fixture.container.inFlightSegmentURL(sequence: 0).path))
        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(events.map(\.type) == [.start])
    }

    @Test func test_append_rotatesOnIntervalBoundaryWithContiguousSampleOffsets() async throws {
        // 100 Hz format, 1 s rotation => 100-sample threshold. Rotation is
        // evaluated on buffer boundaries, not split mid-buffer (docs/03
        // §3.1: "evaluated on buffer boundaries, so rotation points are
        // reproducible") — two 60-sample buffers cross the threshold at
        // 120, not exactly 100.
        let fixture = try await Self.makeFixture(rotationSeconds: 1)
        try await fixture.segmenter.beginRecording()

        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 60))
        try await fixture.segmenter.append(samples: [Float](repeating: 0.2, count: 60))  // crosses the threshold at 120
        try await fixture.segmenter.append(samples: [Float](repeating: 0.3, count: 60))  // into the new segment
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.segments.count == 2)
        #expect(manifest.segments[0].sequence == 0)
        #expect(manifest.segments[0].startSample == 0)
        #expect(manifest.segments[0].sampleCount == 120)
        #expect(manifest.segments[1].sequence == 1)
        #expect(manifest.segments[1].startSample == 120)
        #expect(manifest.segments[1].sampleCount == 60)
        #expect(manifest.validates())
    }

    @Test func test_segments_areRenamedFromInFlightToFinalNames() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))
        _ = try await fixture.segmenter.stop()

        #expect(!FileManager.default.fileExists(atPath: fixture.container.inFlightSegmentURL(sequence: 0).path))
        #expect(FileManager.default.fileExists(atPath: fixture.container.segmentURL(sequence: 0).path))
    }

    @Test func test_pauseThenResume_recordsAnExplicitGapAndContinuesTheSequence() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))

        try await fixture.segmenter.pause()
        fixture.clock.advance(by: 5)  // 5 s gap at 100 Hz => 500 samples
        try await fixture.segmenter.resume()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.2, count: 10))
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.segments.count == 2)
        // Segment 1 continues from segment 0's sample count, not from any
        // gap-inflated offset — gaps are canonical-timeline math (NSP-025),
        // not per-segment startSample math (docs/03 §4).
        #expect(manifest.segments[1].startSample == 10)

        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        let resumeEvent = events.first { $0.type == .resume }
        #expect(resumeEvent?.payload == .object(["gapSamples": .number(500)]))
    }

    @Test func test_interruptionBeganThenEnded_recordsTheCauseAndAGap() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))

        try await fixture.segmenter.interruptionBegan(cause: .phoneCall)
        fixture.clock.advance(by: 2)
        try await fixture.segmenter.interruptionEnded()
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.segments.count == 2)
        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(events.contains { $0.type == .interruptionBegan(cause: .phoneCall) })
        #expect(events.contains { $0.type == .interruptionEnded })
    }

    @Test func test_rotateForRouteChange_closesTheSegmentAndRecordsTheEndpoints() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))

        try await fixture.segmenter.rotateForRouteChange(from: .builtInMic, to: .bluetooth)
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.segments.count == 2)
        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(events.contains { $0.type == .routeChange(from: .builtInMic, to: .bluetooth) })
    }

    @Test func test_addMarker_recordsAnEventWithoutRotating() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))

        try await fixture.segmenter.addMarker(kind: .important)
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.segments.count == 1)
        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(events.contains { $0.type == .marker(kind: .important) })
    }

    @Test func test_addMarker_midSegment_returnsAndRecordsTheInFlightSampleOffsetNotTheSegmentStart() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 30))

        let offset = try await fixture.segmenter.addMarker(kind: .actionItem)

        #expect(offset == 30)
        let events = try await fixture.timelineEventRepository.fetchAll(meetingID: fixture.meetingID)
        let markerEvent = events.first { $0.type == .marker(kind: .actionItem) }
        #expect(markerEvent?.sampleOffset == 30)
    }

    @Test func test_stop_persistsEverySegmentToTheRepository() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))
        _ = try await fixture.segmenter.stop()

        let stored = try await fixture.segmentRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(stored.count == 1)
        #expect(stored[0].transferState == .local)
        #expect(stored[0].sha256 != nil)
    }

    @Test func test_stop_producesASealedValidatingManifest() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.segmenter.beginRecording()
        try await fixture.segmenter.append(samples: [Float](repeating: 0.1, count: 10))
        let manifest = try await fixture.segmenter.stop()

        #expect(manifest.integrity.sealed)
        #expect(manifest.sealedAt != nil)
        #expect(manifest.validates())
    }
}
