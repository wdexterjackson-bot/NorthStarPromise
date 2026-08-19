/// Whether a capability-detected on-device model can run right now (docs/04
/// §2, verbatim case list). A missing capability degrades to "no output,"
/// never to a silent cloud fallback (Invariant I5).
public enum ModelAvailability: Sendable, Hashable, Codable, CaseIterable {
    case available
    case downloading
    case unsupportedOS
    case unavailable
}
