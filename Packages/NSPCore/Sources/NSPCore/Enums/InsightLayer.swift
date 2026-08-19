/// Which layered output an `Insight` belongs to (docs/02 §2). The thin M1
/// slice generates `.flashRecap` and `.executiveSummary`; the rest land M3.
public enum InsightLayer: String, Sendable, Hashable, Codable, CaseIterable {
    case flashRecap
    case executiveSummary
    case detailedNotes
    case chapter
    case takeaway
    case risk
    case openQuestion
}

/// `.said` and `.agreed` are grounded claims; `.aiSuggests` is not, and an
/// `Insight` with empty `evidence` must use `.aiSuggests` — never collapse
/// these into each other (Invariant I4, docs/02 §2, `Insight.claimKind`).
public enum ClaimKind: String, Sendable, Hashable, Codable, CaseIterable {
    case said
    case agreed
    case aiSuggests
}

/// Review status of a generated `Insight` (docs/02 §2, `Insight.approvalState`).
/// `.locked` sections survive regeneration byte-identical (`SUM-002`).
public enum ApprovalState: String, Sendable, Hashable, Codable, CaseIterable {
    case draft
    case edited
    case approved
    case locked
}
