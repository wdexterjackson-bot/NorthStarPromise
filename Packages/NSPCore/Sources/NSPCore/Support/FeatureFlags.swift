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
