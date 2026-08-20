import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPMedia

/// Records every call it receives and lets a test simulate the audio
/// thread delivering buffers via `deliver(_:)`. Local to `NSPMediaTests`
/// (same circular-dependency reasoning as `FakeSegmentAudioEncoder`).
private final class FakeCaptureBackend: CaptureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var onBufferClosure: (@Sendable (UnsafeBufferPointer<Float>) -> Void)?
    private let format: SegmentAudioFormat
    private let shouldFailActivation: Bool

    private(set) var activateCallCount = 0
    private(set) var deactivateCallCount = 0
    private(set) var startEngineCallCount = 0
    private(set) var stopEngineCallCount = 0

    init(format: SegmentAudioFormat, shouldFailActivation: Bool = false) {
        self.format = format
        self.shouldFailActivation = shouldFailActivation
    }

    func activateSession(preferredSampleRate: Double) throws {
        if shouldFailActivation { throw CaptureBackendError.sessionActivationFailed("fixture") }
        lock.lock()
        activateCallCount += 1
        lock.unlock()
    }

    func deactivateSession() throws {
        lock.lock()
        deactivateCallCount += 1
        lock.unlock()
    }

    func inputFormat() throws -> SegmentAudioFormat { format }

    func startEngine(onBuffer: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws {
        lock.lock()
        onBufferClosure = onBuffer
        startEngineCallCount += 1
        lock.unlock()
    }

    func stopEngine() {
        lock.lock()
        onBufferClosure = nil
        stopEngineCallCount += 1
        lock.unlock()
    }

    /// Test hook simulating the audio render thread delivering a buffer.
    func deliver(_ samples: [Float]) {
        lock.lock()
        let closure = onBufferClosure
        lock.unlock()
        samples.withUnsafeBufferPointer { pointer in closure?(pointer) }
    }
}

@Suite("CaptureEngine")
struct CaptureEngineTests {
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
        let engine: CaptureEngine
        let backend: FakeCaptureBackend
        let container: MeetingContainer
        let segmentRepository: GRDBSegmentRepository
        let meetingID: MeetingID
    }

    private static func makeFixture(shouldFailActivation: Bool = false) async throws -> Fixture {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID())
        try await makeMeetingGraph(appDatabase, meetingID: meetingID)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureEngineTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        let segmentRepository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let timelineEventRepository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)
        let deviceID = DeviceID(rawValue: UUID())
        let backend = FakeCaptureBackend(
            format: SegmentAudioFormat(codec: .aacLC, sampleRate: 100, channels: 1, bitRate: 32000),
            shouldFailActivation: shouldFailActivation)

        let engine = CaptureEngine(backend: backend, ringBufferCapacity: 10000) { format in
            Segmenter(
                container: container, audioEncoder: FakeSegmentAudioEncoder(),
                segmentFileSystem: LiveSegmentFileSystem(),
                manifestWriter: ManifestWriter(container: container, fileSystem: LiveManifestFileSystem()),
                segmentRepository: segmentRepository, timelineEventRepository: timelineEventRepository,
                clock: SystemClock(), meetingID: meetingID, deviceID: deviceID, audioFormat: format,
                rotationSeconds: 1000)
        }

        return Fixture(
            engine: engine, backend: backend, container: container, segmentRepository: segmentRepository,
            meetingID: meetingID)
    }

    @Test func test_start_activatesSessionAndOpensSegmentZeroDurably() async throws {
        let fixture = try await Self.makeFixture()

        try await fixture.engine.start()

        #expect(fixture.backend.activateCallCount == 1)
        #expect(fixture.backend.startEngineCallCount == 1)
        // By the time `start()` returns, segment 0's header is already
        // fsync'd — the I1 durable-ack instant (NSP-022's UI wiring reads
        // this same guarantee; here we prove the file is genuinely on disk).
        #expect(FileManager.default.fileExists(atPath: fixture.container.inFlightSegmentURL(sequence: 0).path))
    }

    @Test func test_start_calledTwice_throwsAlreadyCapturing() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.engine.start()

        await #expect(throws: CaptureEngineError.alreadyCapturing) {
            try await fixture.engine.start()
        }
    }

    @Test func test_start_backendActivationFailure_neverOpensASegment() async throws {
        let fixture = try await Self.makeFixture(shouldFailActivation: true)

        await #expect(throws: CaptureEngineError.self) {
            try await fixture.engine.start()
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.container.inFlightSegmentURL(sequence: 0).path))
    }

    @Test func test_deliveredBuffers_reachTheSegmenterAndAreSealedOnStop() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.engine.start()

        fixture.backend.deliver([Float](repeating: 0.1, count: 50))
        // The drain loop polls every 20 ms; give it a couple of cycles.
        try await Task.sleep(nanoseconds: 100_000_000)

        let manifest = try await fixture.engine.stop()

        #expect(manifest.validates())
        #expect(manifest.integrity.sealed)
        let stored = try await fixture.segmentRepository.fetchAll(meetingID: fixture.meetingID)
        #expect(stored.count == 1)
        #expect(stored[0].sampleCount == 50)
        #expect(fixture.backend.stopEngineCallCount == 1)
        #expect(fixture.backend.deactivateCallCount == 1)
    }

    @Test func test_pause_discardsSubsequentBuffersUntilResume() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.engine.start()
        fixture.backend.deliver([Float](repeating: 0.1, count: 20))
        try await Task.sleep(nanoseconds: 100_000_000)

        try await fixture.engine.pause()
        fixture.backend.deliver([Float](repeating: 0.2, count: 999))  // must be discarded, not written anywhere
        try await Task.sleep(nanoseconds: 100_000_000)

        try await fixture.engine.resume()
        fixture.backend.deliver([Float](repeating: 0.3, count: 15))
        try await Task.sleep(nanoseconds: 100_000_000)

        let manifest = try await fixture.engine.stop()

        let totalSamples = manifest.segments.reduce(Int64(0)) { $0 + $1.sampleCount }
        #expect(totalSamples == 35)  // 20 + 15, never 999
    }

    @Test func test_stop_withoutStart_throwsNotCapturing() async throws {
        let fixture = try await Self.makeFixture()

        await #expect(throws: CaptureEngineError.notCapturing) {
            try await fixture.engine.stop()
        }
    }

    @Test func test_routeChanged_rotatesAndRecordsTheEndpoints() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.engine.start()
        fixture.backend.deliver([Float](repeating: 0.1, count: 10))
        try await Task.sleep(nanoseconds: 100_000_000)

        try await fixture.engine.routeChanged(from: .builtInMic, to: .bluetooth)
        let manifest = try await fixture.engine.stop()

        #expect(manifest.segments.count == 2)
    }

    @Test func test_interruption_pausesAndResumesCleanly() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.engine.start()
        fixture.backend.deliver([Float](repeating: 0.1, count: 10))
        try await Task.sleep(nanoseconds: 100_000_000)

        try await fixture.engine.interruptionBegan(cause: .phoneCall)
        try await fixture.engine.interruptionEnded()
        fixture.backend.deliver([Float](repeating: 0.2, count: 10))
        try await Task.sleep(nanoseconds: 100_000_000)

        let manifest = try await fixture.engine.stop()

        #expect(manifest.segments.count == 2)
        #expect(manifest.validates())
    }
}
