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

    public init(
        personID: PersonID,
        workspaceID: WorkspaceID,
        name: String,
        aliases: [String] = [],
        voiceEnrollmentRef: String? = nil,
        contactLink: String? = nil
    ) {
        self.personID = personID
        self.workspaceID = workspaceID
        self.name = name
        self.aliases = aliases
        self.voiceEnrollmentRef = voiceEnrollmentRef
        self.contactLink = contactLink
    }
}
