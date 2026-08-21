import Foundation
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
    /// `.explicit` when a specific calendar date was actually stated
    /// ("March 3rd"), `.inferred` when the model resolved a relative
    /// phrase ("by Friday", "next week") against the meeting's own date,
    /// `.unresolved` when no due date was mentioned at all — a
    /// deliberately open action item, not a missing one (docs/09 Action
    /// Items: "open items with no timetable" are a real, supported case,
    /// not an extraction gap).
    public let date: ResolvedValue<Date>

    public init(text: String, evidence: EvidenceSpan, date: ResolvedValue<Date> = .unresolved) {
        self.text = text
        self.evidence = evidence
        self.date = date
    }
}
