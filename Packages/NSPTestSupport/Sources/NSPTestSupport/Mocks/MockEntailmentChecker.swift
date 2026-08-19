import NSPIntelligence
import NSPPolicy

/// Verdicts scripted per fixture (docs/04 §2.1). With no scripted verdicts,
/// defaults to `.entailed(confidence: 1.0)` for every claim — the
/// permissive default a test overrides only when it specifically wants to
/// exercise a downgrade or drop.
public actor MockEntailmentChecker: EntailmentChecker {
    private let scriptedVerdicts: [EntailmentVerdict]

    public init(scriptedVerdicts: [EntailmentVerdict] = []) {
        self.scriptedVerdicts = scriptedVerdicts
    }

    public func check(_ claims: [ClaimUnderTest]) async throws -> [EntailmentVerdict] {
        guard scriptedVerdicts.isEmpty else { return scriptedVerdicts }
        return claims.map { _ in .entailed(confidence: 1.0) }
    }

    public func checkRemote(_ claims: [ClaimUnderTest], grant: ProcessingGrant) async throws -> [EntailmentVerdict] {
        try await check(claims)
    }
}
