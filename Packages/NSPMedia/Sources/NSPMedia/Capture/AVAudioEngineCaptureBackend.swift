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

    public init() {}

    public func activateSession(preferredSampleRate: Double) async throws {
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

        // Fresh per `startEngine` call, not a stored property — a new
        // recording never inherits gain state from a previous one.
        let dynamicsProcessor = AudioDynamicsProcessor(sampleRate: format.sampleRate)

        input.removeTap(onBus: 0)
        // The tap block runs on the audio render thread: it only copies
        // pointers out, never allocates or awaits (docs/03 §2). Multi-
        // channel hardware is downmixed to the first channel — our target
        // is mono (docs/03 §2.1); true downmixing is a follow-up.
        // `dynamicsProcessor.process` mutates the tap's own buffer in place
        // before the read-only view is built, so both the encoded audio and
        // the level meter downstream see the processed signal, not raw
        // input.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let mutablePointer = UnsafeMutableBufferPointer(start: channelData[0], count: frameLength)
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
