/// A custom-vocabulary term. Every entry is inspectable and individually
/// deletable, whether it was user-entered or learned from correction memory
/// (docs/02 §2, docs/01 §3 "NSPIntelligence").
public struct GlossaryEntry: Sendable, Hashable, Codable, Identifiable {
    public let glossaryEntryID: GlossaryEntryID
    public var id: GlossaryEntryID { glossaryEntryID }
    public let workspaceID: WorkspaceID

    public var term: String
    public var pronunciationHints: [String]
    public var origin: GlossaryEntryOrigin

    public init(
        glossaryEntryID: GlossaryEntryID,
        workspaceID: WorkspaceID,
        term: String,
        pronunciationHints: [String] = [],
        origin: GlossaryEntryOrigin
    ) {
        self.glossaryEntryID = glossaryEntryID
        self.workspaceID = workspaceID
        self.term = term
        self.pronunciationHints = pronunciationHints
        self.origin = origin
    }
}

/// Whether a term was typed by a user or inferred from correction memory
/// (docs/02 §2, "learned-vs-user-entered").
public enum GlossaryEntryOrigin: String, Sendable, Hashable, Codable, CaseIterable {
    case userEntered
    case learned
}
