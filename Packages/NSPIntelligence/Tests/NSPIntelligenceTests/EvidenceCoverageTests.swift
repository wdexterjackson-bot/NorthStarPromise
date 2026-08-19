import Testing

/// I4 gate (docs/10 §2, "I4 — Every generated claim carries evidence").
/// Needs the summarize→bind→verify pipeline and fixture meetings with
/// generated insights — neither exists yet. Remove `.disabled` and
/// implement when `NSP-040`…`NSP-046` land.
@Suite("I4 gate — evidence coverage (NSPIntelligence)")
struct EvidenceCoverageTests {
    @Test(.disabled("needs the summarize→bind→verify pipeline — lands with NSP-040…NSP-046"))
    func test_evidenceCoverage_allActions_resolve() {
        // Runs the full pipeline over every fixture meeting and asserts:
        // 100% of Action/Decision rows leaving .proposed carry >=1
        // EvidenceSpan; every span resolves to a live transcript turn range
        // and playable sample range, or is explicitly marked stale; any
        // Insight with empty evidence has claimKind == .aiSuggests
        // (docs/10 §2).
    }
}
