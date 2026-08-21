/// One case per user-visible, incomplete capability. Default off; a flag
/// fully on for one release is removed in the same PR (docs/11 §10).
public enum FeatureFlag: String, Sendable, CaseIterable, Codable {
    /// Live transcript preview on iPhone while a Watch recording is in
    /// flight. Owner: capture team. Ticket: NSP-065. Remove by: M2 exit.
    case watchLiveTranscriptPreview

    /// iPad Pencil canvas with stroke-to-audio seeking. Owner: iPad team.
    /// Ticket: NSP-100. Remove by: M4 exit.
    case iPadPencilCanvas

    /// Cloud-backed summarization when on-device generation is unavailable
    /// or lower quality. Owner: intelligence team. Ticket: NSP-045.
    /// Remove by: M3 exit.
    case cloudSummarization

    /// Tier-3 FFT-based spectral noise suppression (Wiener-style spectral
    /// gating with a spectral floor) in the capture render tap, layered
    /// after tier 1 (`AVAudioEngine` voice processing) and before tier 2
    /// (`AudioDynamicsProcessor`). Default off — battery/CPU cost on Watch
    /// and real-room tuning of its oversubtraction/floor/noise-EMA
    /// constants are unmeasured pending `CLAUDE.md` §7's hardware
    /// validation gate (docs/03 §2.6). Owner: capture team. Ticket: none —
    /// ad hoc addition, not tracked in docs/09-BACKLOG.md. Remove by:
    /// folded into the always-on pipeline once hardware-validated, or
    /// removed if rejected.
    case tier3SpectralNoiseSuppression

    /// Pre-scheduling a recording (manual or calendar-imported) with a
    /// mandatory Start/Skip local notification and unattended auto-stop
    /// (docs/07 §2.1). Default off — needs a device spike on EventKit
    /// full-access behavior and on background survival of the auto-stop
    /// timer before it's ready to enable (`CLAUDE.md` §7). Owner: capture
    /// team. Ticket: NSP-149. Remove by: folded in once both spikes clear.
    case scheduledRecording
}

/// Read-only flag lookup, injected so views and view models never read a
/// global (docs/11 §4).
public protocol FeatureFlagProviding: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
}

/// All flags off — the shipping default for anything not yet wired to a
/// remote-config or build-setting-backed provider.
public struct AllFlagsOffProvider: FeatureFlagProviding {
    public init() {}
    public func isEnabled(_ flag: FeatureFlag) -> Bool { false }
}
