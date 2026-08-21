import NSPCore

/// One decision candidate `LiveOnDeviceSummarizer.extractDecisionCandidates`
/// found and could ground — same shape as `ActionCandidate`. `approver`
/// stays `.unresolved` for this pass (attributing a decision to a person
/// happens via meeting attendance in the People feature, not a per-decision
/// approver field) — a documented scope cut, not a gap in the extraction
/// itself.
public struct DecisionCandidate: Sendable {
    public let text: String
    public let evidence: EvidenceSpan

    public init(text: String, evidence: EvidenceSpan) {
        self.text = text
        self.evidence = evidence
    }
}
