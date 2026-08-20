import NSPCore

/// One action-item candidate `LiveOnDeviceSummarizer.extractActionCandidates`
/// found and could ground — not an `Insight` (there's no `.actionItem`
/// `InsightLayer`; `Action` is its own domain type), so this is its own
/// small carrier between NSPIntelligence's generation and the app layer's
/// `Action` insert. `evidence` is already real and grounded (produced by
/// `EvidenceGrounder`) by the time a caller sees one of these — an
/// ungrounded candidate never becomes one.
public struct ActionCandidate: Sendable {
    public let text: String
    public let evidence: EvidenceSpan

    public init(text: String, evidence: EvidenceSpan) {
        self.text = text
        self.evidence = evidence
    }
}
