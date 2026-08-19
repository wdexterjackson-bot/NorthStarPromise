import NSPCore
import NSPPolicy

/// docs/04 §2, verbatim.
public struct ClaimUnderTest: Sendable {
    public let claimText: String
    /// The quoted evidence, verbatim.
    public let spanText: String
    public let proposedKind: ClaimKind

    public init(claimText: String, spanText: String, proposedKind: ClaimKind) {
        self.claimText = claimText
        self.spanText = spanText
        self.proposedKind = proposedKind
    }
}

/// docs/04 §2, verbatim. `.underdetermined` downgrades a claim to
/// `.aiSuggests`; `.contradicted` drops it and logs it for evals — never
/// silently kept (docs/04 §4.2, Invariant I4).
public enum EntailmentVerdict: Sendable, Hashable {
    case entailed(confidence: Double)
    case underdetermined(confidence: Double)
    case contradicted(confidence: Double)
}

/// docs/04 §2, verbatim.
public protocol EntailmentChecker: Sendable {
    func check(_ claims: [ClaimUnderTest]) async throws -> [EntailmentVerdict]
    func checkRemote(_ claims: [ClaimUnderTest], grant: ProcessingGrant) async throws -> [EntailmentVerdict]
}
