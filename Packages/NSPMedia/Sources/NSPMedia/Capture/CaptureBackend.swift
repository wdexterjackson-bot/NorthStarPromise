import Foundation

/// Typed, exhaustive error enum for capture backends (docs/11 §2).
public enum CaptureBackendError: Error, Sendable, Hashable {
    case sessionActivationFailed(String)
    case noInputAvailable
    case engineStartFailed(String)
    /// The user denied (or has not yet granted) microphone access. Distinct
    /// from `sessionActivationFailed` because the fix is "go grant it in
    /// Settings," not a retry.
    case permissionDenied
}

/// What `CaptureEngine` needs from the platform audio stack (docs/03 §2),
/// protocol-injected so tests never touch real hardware (docs/11 §4). Scope
/// here is iOS/iPadOS foreground recording — watchOS's background-recording
/// affordance is `NSP-002`'s hardware spike and explicitly deferred.
public protocol CaptureBackend: Sendable {
    /// Requests microphone permission if it hasn't been decided yet, then
    /// configures and activates the audio session (docs/03 §2.1: iOS
    /// `.playAndRecord` / `.spokenAudio`, falling back to `.default`) at
    /// `preferredSampleRate`. Throws `.permissionDenied` rather than
    /// silently activating a session that will only ever capture silence.
    /// The *actual* format capture ends up in is read back afterward via
    /// `inputFormat()` — hardware doesn't always grant exactly what was
    /// requested.
    func activateSession(preferredSampleRate: Double) async throws
    func deactivateSession() throws

    /// The input format now in effect, after `activateSession`. Segments
    /// are described by whatever this reports, not by the preferred rate
    /// that was requested.
    func inputFormat() throws -> SegmentAudioFormat

    /// Starts the engine and installs a render tap. `onBuffer` is called
    /// from the real-time audio thread — it must never allocate, log, or
    /// hop actors (docs/03 §2); the real backend's tap only copies samples
    /// into the caller-owned ring buffer.
    func startEngine(onBuffer: @escaping @Sendable (UnsafeBufferPointer<Float>) -> Void) throws
    func stopEngine()
}
