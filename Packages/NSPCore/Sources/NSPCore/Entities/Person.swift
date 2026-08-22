/// A participant, scoped to one workspace (docs/02 §2, "Supporting entities").
/// Names are never invented without evidence — resolution happens in
/// `NSPIntelligence`, this type just holds the result.
public struct Person: Sendable, Hashable, Codable, Identifiable {
    public let personID: PersonID
    public var id: PersonID { personID }
    public let workspaceID: WorkspaceID

    public var name: String
    public var aliases: [String]
    public var voiceEnrollmentRef: String?
    public var contactLink: String?
    /// Freeform relationship labels ("Direct report", "Board", "Vendor") —
    /// deliberately not an enum. An executive's roster doesn't fit one
    /// fixed taxonomy (People recommendation, 2026-08-22).
    public var tags: [String]
    /// Freeform context the user writes about this person directly —
    /// "prefers async updates", "reports to Dana" — never AI-generated, so
    /// it carries no `EvidenceSpan` (Invariant I4 doesn't apply; same
    /// reasoning as a manually-created `Action`).
    public var notes: String?

    public init(
        personID: PersonID,
        workspaceID: WorkspaceID,
        name: String,
        aliases: [String] = [],
        voiceEnrollmentRef: String? = nil,
        contactLink: String? = nil,
        tags: [String] = [],
        notes: String? = nil
    ) {
        self.personID = personID
        self.workspaceID = workspaceID
        self.name = name
        self.aliases = aliases
        self.voiceEnrollmentRef = voiceEnrollmentRef
        self.contactLink = contactLink
        self.tags = tags
        self.notes = notes
    }
}
