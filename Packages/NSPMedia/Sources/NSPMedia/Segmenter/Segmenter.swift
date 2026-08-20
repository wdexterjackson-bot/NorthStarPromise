import Foundation
import NSPCore
import NSPPersistence

/// Why a segment rotated (docs/03 §3.1, §3.3). Thermal/battery/storage
/// sealed-stop escalation and the health-signal warnings that precede them
/// (docs/03 §2.5) are out of this pass's scope — `.thermalEscalation` and
/// `.storageWarning` exist here so the vocabulary matches the spec, but
/// nothing in this package triggers them yet.
public enum RotationReason: Sendable, Hashable {
    case interval
    case pause
    case interruptionBegan
    case stop
    case routeChange
    case formatChange
    case thermalEscalation
    case storageWarning
}

/// Typed, exhaustive error enum for `Segmenter` (docs/11 §2).
public enum SegmenterError: Error, Sendable, Hashable {
    case noSegmentOpen
    case segmentAlreadyOpen
}

/// Owns segment rotation and the atomic close protocol (docs/03 §3,
/// NSP-020). An actor: every state transition — open, append, rotate,
/// pause, resume, stop — is serialized, so a route-change rotation can
/// never race an interval rotation.
///
/// Deliberately narrow: `CaptureEngine` decides *when* audio arrives and
/// *why* a rotation was requested; `ManifestWriter` (NSP-014) owns the
/// WAL/seal mechanics; this type is the thing that sequences segment
/// files and drives both correctly, in the order docs/03 §3.2 specifies.
public actor Segmenter {
    private let container: MeetingContainer
    private let audioEncoder: any SegmentAudioEncoder
    private let segmentFileSystem: any SegmentFileSystem
    private let manifestWriter: ManifestWriter
    private let segmentRepository: any SegmentRepository
    private let timelineEventRepository: any TimelineEventRepository
    private let clock: any Clock
    private let meetingID: MeetingID
    private let deviceID: DeviceID
    private let audioFormat: SegmentAudioFormat
    private let rotationSamples: Int64

    private var currentSequence = 0
    private var cumulativeSampleCount: Int64 = 0
    private var samplesInCurrentSegment: Int64 = 0
    private var isSegmentOpen = false
    private var pauseStartedAt: Date?
    private var closedSegments: [ManifestSegmentRecord] = []

    public init(
        container: MeetingContainer, audioEncoder: some SegmentAudioEncoder,
        segmentFileSystem: some SegmentFileSystem, manifestWriter: ManifestWriter,
        segmentRepository: some SegmentRepository, timelineEventRepository: some TimelineEventRepository,
        clock: some Clock, meetingID: MeetingID, deviceID: DeviceID,
        audioFormat: SegmentAudioFormat = .iOSDefault, rotationSeconds: Double = 60
    ) {
        self.container = container
        self.audioEncoder = audioEncoder
        self.segmentFileSystem = segmentFileSystem
        self.manifestWriter = manifestWriter
        self.segmentRepository = segmentRepository
        self.timelineEventRepository = timelineEventRepository
        self.clock = clock
        self.meetingID = meetingID
        self.deviceID = deviceID
        self.audioFormat = audioFormat
        self.rotationSamples = Int64(rotationSeconds * Double(audioFormat.sampleRate))
    }

    /// Opens segment 0 and fsyncs its header before returning — an
    /// armed-but-empty segment is a valid, zero-length-audio file, and the
    /// moment this returns is the durable-acknowledgement instant I1
    /// requires (docs/03 §3.2's closing note; NSP-022 owns surfacing this
    /// timing to the UI, not this type).
    public func beginRecording() async throws {
        try await openSegment()
        try await recordTimelineEvent(.start)
    }

    /// Appends captured samples to the open segment, rotating on the
    /// sample-driven interval boundary (docs/03 §3.1) when the threshold is
    /// crossed.
    public func append(samples: [Float]) async throws {
        guard isSegmentOpen else { throw SegmenterError.noSegmentOpen }
        try audioEncoder.append(samples)
        samplesInCurrentSegment += Int64(samples.count)
        if samplesInCurrentSegment >= rotationSamples {
            try await rotate(reason: .interval)
        }
    }

    /// Forced rotation — format change or an escalating health condition
    /// (docs/03 §3.1). Closes the current segment and opens the next one
    /// immediately; a plain rotation isn't itself a timeline event (there's
    /// no such `TimelineEventType` case — only what *caused* it is, and for
    /// a route change that's `rotateForRouteChange`, since only the caller
    /// knows the actual from/to endpoints).
    public func rotate(reason: RotationReason) async throws {
        try await closeCurrentSegment()
        try await openSegment()
    }

    /// Route change (docs/03 §2.3): rotate at the boundary and record which
    /// endpoints changed. Keeps every segment homogeneous in format/channel
    /// count, since segments must be independently decodable (I3).
    public func rotateForRouteChange(from: AudioRouteEndpoint, to: AudioRouteEndpoint) async throws {
        try await closeCurrentSegment()
        try await openSegment()
        try await recordTimelineEvent(.routeChange(from: from, to: to))
    }

    /// Closes the segment and does *not* open a successor until `resume`
    /// (docs/03 §3.3) — the gap between here and `resume` is recorded
    /// explicitly, never interpolated.
    public func pause() async throws {
        try await closeCurrentSegment()
        pauseStartedAt = clock.now()
        try await recordTimelineEvent(.pause)
    }

    /// Opens segment `n+1`; `startSample` continues from the pre-pause
    /// total, so the gap is explicit rather than implied (docs/03 §3.3).
    public func resume() async throws {
        let gapSamples = gapSamplesSincePause()
        pauseStartedAt = nil
        try await openSegment()
        try await recordTimelineEvent(.resume, gapSamples: gapSamples)
    }

    /// `.began`: close the segment through the full protocol and record the
    /// interruption (docs/03 §2.4). Recording state moves to `Interrupted`
    /// — that transition itself is `CaptureEngine`'s concern, not this
    /// type's.
    public func interruptionBegan(cause: InterruptionCause) async throws {
        try await closeCurrentSegment()
        pauseStartedAt = clock.now()
        try await recordTimelineEvent(.interruptionBegan(cause: cause))
    }

    /// `.ended` with `.shouldResume`: open the next segment and record the
    /// gap, same shape as `resume()` (docs/03 §2.4).
    public func interruptionEnded() async throws {
        let gapSamples = gapSamplesSincePause()
        pauseStartedAt = nil
        try await openSegment()
        try await recordTimelineEvent(.interruptionEnded, gapSamples: gapSamples)
    }

    /// Records a marker at the current sample offset (docs/03 §3.3)
    /// without touching segment state. Returns that offset so a caller
    /// anchoring a `NoteBlock` to this exact moment (docs/07 §4, "Markers
    /// are notes") doesn't have to re-derive it.
    @discardableResult
    public func addMarker(kind: MarkerKind) async throws -> Int64 {
        try await recordTimelineEvent(.marker(kind: kind))
    }

    /// The current sample position — same math `recordTimelineEvent` uses,
    /// without recording anything. For continuous note-taking (iPad's
    /// ruled-paper canvas, docs/07 §5): a typed line isn't a timeline
    /// event, just a `NoteBlock` that wants an accurate anchor.
    public func currentSampleOffset() -> Int64 {
        cumulativeSampleCount + samplesInCurrentSegment
    }

    /// Closes the final segment, then seals the manifest (docs/03 §3.4) —
    /// the only place `ManifestWriter.seal` is called on the happy path.
    public func stop() async throws -> Manifest {
        if isSegmentOpen {
            try await closeCurrentSegment()
        }
        try await recordTimelineEvent(.stop)

        var manifest = Manifest(
            meetingID: meetingID, deviceID: deviceID, captureMode: .phone,
            audioFormat: Manifest.AudioFormat(
                codec: audioFormat.codec, sampleRate: audioFormat.sampleRate, channels: audioFormat.channels,
                bitRate: audioFormat.bitRate),
            createdAt: clock.now())
        manifest.segments = closedSegments

        let sealedAt = clock.now()
        try await manifestWriter.seal(manifest, sealedAt: sealedAt)
        // `seal` writes its own sealed copy to disk; mirror that mutation
        // here so the value this call returns matches what was persisted,
        // rather than the pre-seal draft.
        manifest.sealedAt = sealedAt
        manifest.integrity.sealed = true
        return manifest
    }

    // MARK: - Atomic close protocol (docs/03 §3.2)

    private func openSegment() async throws {
        guard !isSegmentOpen else { throw SegmenterError.segmentAlreadyOpen }
        let url = container.inFlightSegmentURL(sequence: currentSequence)
        try audioEncoder.startSegment(at: url, format: audioFormat)
        // The header alone, fsync'd before any frame arrives — an
        // armed-but-empty segment is still a valid file (docs/03 §3.2).
        try segmentFileSystem.fsync(at: url)
        isSegmentOpen = true
        samplesInCurrentSegment = 0
    }

    private func closeCurrentSegment() async throws {
        guard isSegmentOpen else { return }
        let sequence = currentSequence
        let inFlightURL = container.inFlightSegmentURL(sequence: sequence)
        let finalURL = container.segmentURL(sequence: sequence)

        // 1. Encoder flushes the trailer.
        try audioEncoder.finishWriting()
        // 2. fsync — bytes are on stable storage, not the page cache.
        try segmentFileSystem.fsync(at: inFlightURL)
        // 3. Hash the exact bytes that survived the fsync.
        let sha256 = try segmentFileSystem.sha256(ofFileAt: inFlightURL)
        // 4. Atomic rename — the final name claims "complete and hashed."
        try segmentFileSystem.renameItem(at: inFlightURL, to: finalURL)

        let segmentID = SegmentID(rawValue: UUID())
        let startSample = cumulativeSampleCount
        let sampleCount = samplesInCurrentSegment
        let closedAt = clock.now()

        // 5. WAL append, not a manifest rewrite (docs/03 §3.2 step 5).
        let record = ManifestSegmentRecord(
            sequence: sequence, segmentID: segmentID, file: "segments/\(finalURL.lastPathComponent)",
            startSample: startSample, sampleCount: sampleCount, sha256: sha256, closedAt: closedAt)
        try await manifestWriter.append(.segment(record))
        closedSegments.append(record)

        // 6. Durable locally before the outbox may see it (I2).
        let segment = Segment(
            segmentID: segmentID, meetingID: meetingID, deviceID: deviceID, sequence: sequence,
            codec: audioFormat.codec, sampleRate: audioFormat.sampleRate, channels: audioFormat.channels,
            bitRate: audioFormat.bitRate, startSample: startSample, sampleCount: sampleCount, sha256: sha256,
            localURL: finalURL, transferState: .local)
        try await segmentRepository.insert(segment, at: closedAt)

        // 7. NSPTransfer.enqueue(segmentID) — Watch/Transfer is deferred
        // (this session's own scope decision); iPhone-originated segments
        // have nowhere to transfer to yet. Re-add this call when NSPTransfer
        // work resumes.

        cumulativeSampleCount += sampleCount
        currentSequence += 1
        isSegmentOpen = false
        samplesInCurrentSegment = 0
    }

    // MARK: - Timeline events

    /// Every other caller (`start`, `pause`, `resume`, route change,
    /// interruption) closes and/or opens a segment immediately before
    /// calling this, which always zeroes `samplesInCurrentSegment` — so
    /// `cumulativeSampleCount` alone happened to be correct for them.
    /// `addMarker` is the one caller that doesn't touch segment state, so
    /// it needs the in-flight segment's samples added in too, or a marker
    /// dropped mid-segment would be stamped at that segment's *start*
    /// instead of the actual moment (up to a full rotation interval off).
    @discardableResult
    private func recordTimelineEvent(_ type: TimelineEventType, gapSamples: Int64? = nil) async throws -> Int64 {
        let sampleOffset = cumulativeSampleCount + samplesInCurrentSegment
        let payload: JSONValue? = gapSamples.map { .object(["gapSamples": .number(Double($0))]) }
        let event = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), meetingID: meetingID, deviceID: deviceID, type: type,
            sampleOffset: sampleOffset, wallClock: clock.now(), payload: payload)
        try await manifestWriter.append(
            .timelineEvent(
                ManifestTimelineRecord(
                    type: event.type, sampleOffset: event.sampleOffset, wallClock: event.wallClock,
                    payload: event.payload)))
        try await timelineEventRepository.append(event, at: clock.now())
        return sampleOffset
    }

    private func gapSamplesSincePause() -> Int64 {
        guard let pauseStartedAt else { return 0 }
        let elapsedSeconds = clock.now().timeIntervalSince(pauseStartedAt)
        return Int64((elapsedSeconds * Double(audioFormat.sampleRate)).rounded())
    }
}
