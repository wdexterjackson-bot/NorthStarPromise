/// The thirteen content block kinds a `NoteBlock` can be (docs/02 §2).
public enum NoteBlockType: String, Sendable, Hashable, Codable, CaseIterable {
    case richText
    case checklist
    case decision
    case action
    case quote
    case question
    case code
    case table
    case sketch
    case photo
    case linkPreview
    case file
    case transcriptExcerpt
}

/// `.shared` is visible in every export and share; `.privateToAuthor` is
/// excluded by default and the exclusion is enforced in export code, not the
/// UI (docs/02 §2, `NoteBlock.privacy`; NSP-105).
public enum BlockPrivacy: String, Sendable, Hashable, Codable, CaseIterable {
    case shared
    case privateToAuthor
}

/// Whether a note block has been proposed into, or merged into, the recap.
/// AI never sets `.mergedIntoRecap` directly — only a user approval does
/// (docs/02 §2, `NoteBlock.mergeState`).
public enum MergeState: Sendable, Hashable, Codable {
    case standalone
    case proposedForRecap(diffID: String)
    case mergedIntoRecap(insightID: InsightID)
}
