/// A participant, scoped to one workspace (docs/02 §2, "Supporting entities").
/// Names are never invented without evidence — resolution happens in
/// `NSPIntelligence`, this type just holds the result.
public struct Person: Sendable, Hashable, Codable, Identifiable {
    public let personID: PersonID
    public var id: PersonID { personID }
    public let workspaceID: WorkspaceID

    public var name: String
    public var aliases: [String]
    /// Freeform job title ("VP Sales," "Chief of Staff") — added for "The
    /// First Hour" wizard (2026-08-22), which asks for it on the self-Person
    /// in step 1, but it's a general field any Person can carry, shown on
    /// People/Thread/Project detail screens too. Never required.
    public var role: String?
    /// Freeform employer/org name ("Acme Inc," "Board of Directors") — same
    /// wizard, same "helps but never required" status as `role`. Kept
    /// separate from `tags` deliberately: `tags` describes this person's
    /// *relationship* to the workspace owner ("Vendor," "Board"), while
    /// `organization` is a fact about the person themselves, independent of
    /// that relationship.
    public var organization: String?
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
    /// "Don't transcribe me" (Ambient Mode Phase 2, "Overheard"
    /// recommendation, 2026-08-22) — when a person known to speak in this
    /// workspace has opted out, `AmbientCoordinator` honors it at the
    /// rolling-buffer level, before anything is evaluated for relevance.
    /// Enforcing this precisely needs real-time speaker attribution on the
    /// live ambient stream, which doesn't exist yet — until it does, this
    /// flag is honored coarsely (excluding this person from thread/person
    /// matching results, never surfacing a suggestion attributed to them),
    /// not by detecting and silencing their voice specifically.
    public var ambientListeningOptOut: Bool

    public init(
        personID: PersonID,
        workspaceID: WorkspaceID,
        name: String,
        aliases: [String] = [],
        role: String? = nil,
        organization: String? = nil,
        voiceEnrollmentRef: String? = nil,
        contactLink: String? = nil,
        tags: [String] = [],
        notes: String? = nil,
        ambientListeningOptOut: Bool = false
    ) {
        self.personID = personID
        self.workspaceID = workspaceID
        self.name = name
        self.aliases = aliases
        self.role = role
        self.organization = organization
        self.voiceEnrollmentRef = voiceEnrollmentRef
        self.contactLink = contactLink
        self.tags = tags
        self.notes = notes
        self.ambientListeningOptOut = ambientListeningOptOut
    }
}
