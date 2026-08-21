/// What a recording is *for* — distinct from `CaptureMode` (which device
/// captured it). A `Meeting` is always `.meeting` now: the solo-capture case
/// this type used to also cover moved to `BrainDump`, its own top-level
/// entity, once the app stopped treating a mental note as a disguised
/// meeting (docs/09-BACKLOG.md, "rescoping the meeting-organization data
/// model"). Kept as a real (if currently single-case) type rather than
/// deleted outright — `microphoneProfile` still documents the one real
/// difference a future Meeting-only intent (e.g. a dictation mode) would
/// need to plug into.
public enum RecordingIntent: String, Sendable, Hashable, Codable, CaseIterable {
    /// A recorded meeting/conversation — typically several voices, some at
    /// a distance from the phone. Tied to at most one project.
    case meeting

    /// The microphone tuning this intent asks the capture backend to
    /// request — best-effort (`AVAudioEngineCaptureBackend`'s own doc
    /// comment): real hardware/Simulator support varies, and this never
    /// blocks recording if the preferred tuning isn't available.
    public var microphoneProfile: MicrophoneProfile {
        switch self {
        case .meeting: return .room
        }
    }
}

/// The two microphone tunings `RecordingIntent` maps to — kept as its own
/// type rather than reusing `RecordingIntent` directly in `NSPMedia` so a
/// future third intent (e.g. a dictation mode) doesn't have to also mean a
/// new capture-backend case.
public enum MicrophoneProfile: Sendable, Hashable {
    /// Wider pickup for a larger room and voices further from the device —
    /// an omnidirectional polar pattern where the hardware supports
    /// selecting one.
    case room
    /// Tighter, front-focused pickup for one nearby speaker, rejecting the
    /// rest of the room — a cardioid polar pattern where supported.
    case closeTalk
}
