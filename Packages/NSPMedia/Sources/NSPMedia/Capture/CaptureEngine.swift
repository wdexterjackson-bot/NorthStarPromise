import Foundation
import NSPCore

/// Typed, exhaustive error enum for `CaptureEngine` (docs/11 §2).
public enum CaptureEngineError: Error, Sendable, Hashable {
    case alreadyCapturing
    case notCapturing
    case backendFailure(String)
}

/// Coordinates a `CaptureBackend` and a `Segmenter` into one start/pause/
/// resume/stop surface (docs/03 §2, NSP-019). An actor: the render tap
/// hands samples to an `AudioRingBuffer` from the audio thread; this actor
/// drains it on its own schedule, so nothing on the audio thread ever
/// awaits or allocates.
///
/// The `Segmenter` isn't known until `start()` resolves the backend's
/// *actual* input format (hardware doesn't always grant the preferred
/// sample rate) — `makeSegmenter` is called exactly once, with that real
/// format, so `Segmenter`'s rotation math is never built on a guess.
public actor CaptureEngine {
    private let backend: any CaptureBackend
    private let ringBuffer: AudioRingBuffer
    private let preferredSampleRate: Double
    private let makeSegmenter: @Sendable (SegmentAudioFormat) -> Segmenter

    private var segmenter: Segmenter?
    private var drainTask: Task<Void, Never>?
    private var isCapturing = false
    private var isPaused = false
    private var resolvedFormat: SegmentAudioFormat?

    /// Immutable and internally thread-safe (`AudioLevelMeter`'s own
    /// doc comment explains why), so it's exposed `nonisolated` — the UI
    /// polls it directly rather than awaiting the actor every frame.
    public nonisolated let levelMeter = AudioLevelMeter()

    public init(
        backend: some CaptureBackend, ringBufferCapacity: Int = 96000, preferredSampleRate: Double = 48000,
        makeSegmenter: @escaping @Sendable (SegmentAudioFormat) -> Segmenter
    ) {
        self.backend = backend
        self.ringBuffer = AudioRingBuffer(capacity: ringBufferCapacity)
        self.preferredSampleRate = preferredSampleRate
        self.makeSegmenter = makeSegmenter
    }

    /// Activates the session, resolves the real input format, opens
    /// segment 0 — fsync'd before this returns — and starts the render
    /// tap. Only after this returns has anything durable happened; a
    /// caller must not report `Recording` before it does (Invariant I1;
    /// surfacing that timing to the UI is NSP-022's job, not this type's).
    public func start() async throws {
        guard !isCapturing else { throw CaptureEngineError.alreadyCapturing }

        do {
            try backend.activateSession(preferredSampleRate: preferredSampleRate)
        } catch {
            throw CaptureEngineError.backendFailure("\(error)")
        }

        let format: SegmentAudioFormat
        do {
            format = try backend.inputFormat()
        } catch {
            throw CaptureEngineError.backendFailure("\(error)")
        }

        resolvedFormat = format
        let segmenter = makeSegmenter(format)
        self.segmenter = segmenter
        try await segmenter.beginRecording()

        do {
            try backend.startEngine(onBuffer: { [ringBuffer, levelMeter] samples in
                ringBuffer.write(samples)
                levelMeter.record(samples: samples)
            })
        } catch {
            throw CaptureEngineError.backendFailure("\(error)")
        }

        isCapturing = true
        isPaused = false
        drainTask = Task { [weak self] in await self?.drainLoop() }
    }

    /// Closes the current segment and records a gap; the engine keeps
    /// running so `resume` is instant, but drained samples are discarded
    /// while paused rather than written anywhere (docs/03 §3.3).
    public func pause() async throws {
        guard isCapturing, !isPaused, let segmenter else { throw CaptureEngineError.notCapturing }
        isPaused = true
        try await segmenter.pause()
    }

    public func resume() async throws {
        guard isCapturing, isPaused, let segmenter else { throw CaptureEngineError.notCapturing }
        isPaused = false
        try await segmenter.resume()
    }

    /// Returns the sample offset the marker was recorded at, so a caller
    /// creating a `NoteBlock` for it (docs/07 §4) anchors to the exact
    /// moment rather than re-deriving it.
    @discardableResult
    public func addMarker(kind: MarkerKind) async throws -> Int64 {
        guard isCapturing, let segmenter else { throw CaptureEngineError.notCapturing }
        return try await segmenter.addMarker(kind: kind)
    }

    /// `nil` when nothing is capturing — see `Segmenter.currentSampleOffset()`.
    public func currentSampleOffset() async -> Int64? {
        guard isCapturing, let segmenter else { return nil }
        return await segmenter.currentSampleOffset()
    }

    /// The real, hardware-resolved format `start()` settled on — `nil`
    /// before the first `start()`. Lets a caller convert a persisted
    /// sample offset back into seconds without re-deriving or guessing a
    /// rate (docs/07 §5's iPad canvas restores lines this way).
    public func resolvedAudioFormat() -> SegmentAudioFormat? {
        resolvedFormat
    }

    /// Route change (docs/03 §2.3) — forwarded from whatever observes
    /// `AVAudioSession.routeChangeNotification` (the composition root, not
    /// this type, since notification plumbing isn't capture logic).
    public func routeChanged(from: AudioRouteEndpoint, to: AudioRouteEndpoint) async throws {
        guard isCapturing, !isPaused, let segmenter else { throw CaptureEngineError.notCapturing }
        try await segmenter.rotateForRouteChange(from: from, to: to)
    }

    /// Interruption began (docs/03 §2.4) — forwarded from
    /// `AVAudioSession.interruptionNotification`.
    public func interruptionBegan(cause: InterruptionCause) async throws {
        guard isCapturing, !isPaused, let segmenter else { throw CaptureEngineError.notCapturing }
        isPaused = true
        try await segmenter.interruptionBegan(cause: cause)
    }

    /// Interruption ended with `.shouldResume` (docs/03 §2.4). Without
    /// `.shouldResume`, or after repeated re-activation failure, the
    /// composition root calls `stop()` instead — that escalation policy
    /// lives above this type, not inside it.
    public func interruptionEnded() async throws {
        guard isCapturing, isPaused, let segmenter else { throw CaptureEngineError.notCapturing }
        try backend.activateSession(preferredSampleRate: preferredSampleRate)
        isPaused = false
        try await segmenter.interruptionEnded()
    }

    /// Stops the engine, flushes whatever's left in the ring buffer, closes
    /// the final segment, and seals the manifest (docs/03 §3.4).
    @discardableResult
    public func stop() async throws -> Manifest {
        guard isCapturing, let segmenter else { throw CaptureEngineError.notCapturing }
        drainTask?.cancel()
        drainTask = nil
        backend.stopEngine()
        try? backend.deactivateSession()
        isCapturing = false
        isPaused = false

        let remaining = ringBuffer.drain()
        if !remaining.isEmpty {
            try await segmenter.append(samples: remaining)
        }
        let manifest = try await segmenter.stop()
        self.segmenter = nil
        return manifest
    }

    private func drainLoop() async {
        while !Task.isCancelled {
            let samples = ringBuffer.drain()
            if !isPaused, !samples.isEmpty, let segmenter {
                try? await segmenter.append(samples: samples)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
