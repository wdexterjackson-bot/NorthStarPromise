import AVFoundation
import Foundation
import NSPCore

/// The real `CaptureBackend`, backed by `AVAudioEngine` (docs/03 §2.1's
/// primary implementation; `AVAudioRecorder` is retained as a Watch
/// fallback in the spec but that path is watchOS-only and out of this
/// pass's scope). Session category/mode configuration is `#if os(iOS)`-
/// gated since `AVAudioSession` doesn't exist on macOS, where this package
/// still needs to compile for `swift test`.
public final class AVAudioEngineCaptureBackend: CaptureBackend, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let featureFlagProvider: any FeatureFlagProviding

    /// Tier 3 (optional, flag-gated) and tier 2 (always on) — promoted from
    /// `startEngine`-local variables to instance state so `stopEngine` can
    /// flush tier 3's buffered residual through the same chain before
    /// tearing down, rather than silently dropping it (docs/03 §2.6).
    private var spectralNoiseSuppressor: SpectralNoiseSuppressor?
    private var dynamicsProcessor: AudioDynamicsProcessor?
    private var onBuffer: (@Sendable (UnsafeBufferPointer<Float>) -> Void)?

    public init(featureFlagProvider: any FeatureFlagProviding = AllFlagsOffProvider()) {
        self.featureFlagProvider = featureFlagProvider
    }

    public func activateSession(preferredSampleRate: Double, micProfile: MicrophoneProfile) async throws {
        #if os(iOS)
            try await Self.ensureRecordPermission()
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(
                    .playAndRecord, mode: .spokenAudio,
                    options: [])
            } catch {
                // `.spokenAudio` isn't available in every configuration
                // (docs/03 §2.1: "falls back to `.default`").
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [])
                } catch {
                    throw CaptureBackendError.sessionActivationFailed("\(error)")
                }
            }
            do {
                try session.setPreferredSampleRate(preferredSampleRate)
                try session.setPreferredIOBufferDuration(0.020)  // docs/03 §2.1: 20 ms on iOS
                try session.setActive(true)
            } catch {
                throw CaptureBackendError.sessionActivationFailed("\(error)")
            }

            Self.applyMicrophoneProfile(micProfile, session: session)

            // Voice processing contributes noise + echo suppression; its own
            // AGC is explicitly disabled since `AudioDynamicsProcessor` is
            // the only gain-control stage — the two would otherwise fight.
            // Must happen before `inputFormat()`/`startEngine()` read the
            // input node's format, since enabling this can change it. Must
            // also happen before `engine.start()` — Apple's own doc comment
            // on `setVoiceProcessingEnabled` requires the engine be stopped.
            // Best-effort: a rare failure here shouldn't block recording
            // over an enhancement `AudioDynamicsProcessor` doesn't depend
            // on (same reasoning `CaptureEngine.stop()`'s non-fatal
            // `try? backend.deactivateSession()` documents).
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                engine.inputNode.isVoiceProcessingAGCEnabled = false
            } catch {
                // Non-fatal — see doc comment above.
            }
        #endif
    }

    #if os(iOS)
        /// Best-effort polar-pattern selection (`RecordingIntent
        /// .microphoneProfile`'s doc comment) — Simulator, most external
        /// mics, and some iPhone models/OS versions don't expose
        /// `dataSources`/`supportedPolarPatterns` at all, so this silently
        /// no-ops rather than failing recording over a tuning preference —
        /// same non-fatal shape as the voice-processing toggle below.
        private static func applyMicrophoneProfile(_ profile: MicrophoneProfile, session: AVAudioSession) {
            guard let input = session.preferredInput, let dataSources = input.dataSources else { return }
            let preferredPattern: AVAudioSession.PolarPattern = profile == .closeTalk ? .cardioid : .omnidirectional
            guard
                let dataSource = dataSources.first(where: {
                    $0.supportedPolarPatterns?.contains(preferredPattern) == true
                })
            else { return }
            do {
                try dataSource.setPreferredPolarPattern(preferredPattern)
                try input.setPreferredDataSource(dataSource)
            } catch {
                // Non-fatal — see doc comment above.
            }
        }

        /// Without this, `AVAudioEngine` happily starts and taps the input
        /// node even with permission `.undetermined` or `.denied` — no
        /// error, just a render tap that only ever delivers silence. This
        /// is the single call that turns "recording captured nothing" into
        /// an actual, typed failure instead.
        private static func ensureRecordPermission() async throws {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return
            case .denied:
                throw CaptureBackendError.permissionDenied
            case .undetermined:
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw CaptureBackendError.permissionDenied
                }
            @unknown default:
                throw CaptureBackendError.permissionDenied
            }
        }
    #endif

    public func deactivateSession() throws {
        #if os(iOS)
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                throw CaptureBackendError.sessionActivationFailed("\(error)")
            }
        #endif
    }

    public func inputFormat() throws -> SegmentAudioFormat {
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureBackendError.noInputAvailable
        }
        return SegmentAudioFormat(
            codec: .aacLC, sampleRate: Int(format.sampleRate), channels: 1, bitRate: 64000)
    }

    public func startEngine(onBuffer: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureBackendError.noInputAvailable
        }

        // Fresh per `startEngine` call, not persisted across recordings —
        // a new recording never inherits gain or noise-profile state from
        // a previous one. Deciding whether tier 3 is active, and
        // constructing it (which allocates its FFT setup and scratch
        // buffers), happens here rather than inside the tap closure below
        // — that construction must never happen on the audio thread.
        let dynamicsProcessor = AudioDynamicsProcessor(sampleRate: format.sampleRate)
        let spectralNoiseSuppressor: SpectralNoiseSuppressor? =
            featureFlagProvider.isEnabled(.tier3SpectralNoiseSuppression)
            ? SpectralNoiseSuppressor(sampleRate: format.sampleRate) : nil
        self.dynamicsProcessor = dynamicsProcessor
        self.spectralNoiseSuppressor = spectralNoiseSuppressor
        self.onBuffer = onBuffer

        input.removeTap(onBus: 0)
        // The tap block runs on the audio render thread: it only copies
        // pointers out, never allocates or awaits (docs/03 §2). Multi-
        // channel hardware is downmixed to the first channel — our target
        // is mono (docs/03 §2.1); true downmixing is a follow-up. When
        // tier 3 is active it runs first (docs/03 §2.6 explains the
        // ordering), and its output feeds tier 2 exactly as raw samples
        // would have; either way `dynamicsProcessor.process` mutates in
        // place before the read-only view is built, so both the encoded
        // audio and the level meter downstream see the fully processed
        // signal, never raw input.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let rawSamples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

            let processedSamples: UnsafeBufferPointer<Float>
            if let spectralNoiseSuppressor {
                processedSamples = spectralNoiseSuppressor.process(rawSamples)
                guard !processedSamples.isEmpty else { return }
            } else {
                processedSamples = rawSamples
            }

            let mutablePointer = UnsafeMutableBufferPointer(mutating: processedSamples)
            dynamicsProcessor.process(mutablePointer)
            onBuffer(UnsafeBufferPointer(mutablePointer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureBackendError.engineStartFailed("\(error)")
        }
    }

    public func stopEngine() {
        // Tier 3 buffers up to almost one frame of audio internally before
        // it's reconstructed — without draining that now, the tail of
        // every tier-3 recording would be silently short (docs/03 §2.6).
        if let spectralNoiseSuppressor, let dynamicsProcessor, let onBuffer {
            let residual = spectralNoiseSuppressor.flush()
            if !residual.isEmpty {
                let mutablePointer = UnsafeMutableBufferPointer(mutating: residual)
                dynamicsProcessor.process(mutablePointer)
                onBuffer(UnsafeBufferPointer(mutablePointer))
            }
        }
        self.spectralNoiseSuppressor = nil
        self.dynamicsProcessor = nil
        self.onBuffer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
