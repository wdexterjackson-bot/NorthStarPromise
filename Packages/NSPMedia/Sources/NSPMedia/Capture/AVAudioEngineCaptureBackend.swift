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

    public func activateSession(preferredSampleRate: Double) throws {
        #if os(iOS)
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
        #endif
    }

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

        input.removeTap(onBus: 0)
        // The tap block runs on the audio render thread: it only copies
        // pointers out, never allocates or awaits (docs/03 §2). Multi-
        // channel hardware is downmixed to the first channel — our target
        // is mono (docs/03 §2.1); true downmixing is a follow-up.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let pointer = UnsafeBufferPointer(start: channelData[0], count: frameLength)
            onBuffer(pointer)
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
