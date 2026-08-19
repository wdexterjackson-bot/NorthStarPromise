/// A frozen policy snapshot in force for one meeting or workspace
/// (docs/02 §2, "Supporting entities"; docs/06). `NSPPolicy` is the only
/// module permitted to construct or evaluate one at runtime.
public struct Policy: Sendable, Hashable, Codable, Identifiable {
    public let policyID: PolicyID
    public var id: PolicyID { policyID }
    public let workspaceID: WorkspaceID

    public var retentionDays: Int?
    public var defaultProcessingMode: ProcessingMode
    public var announcementRequired: Bool
    public var blockedDomains: [String]
    public var blockedLocations: [String]

    public init(
        policyID: PolicyID,
        workspaceID: WorkspaceID,
        retentionDays: Int? = nil,
        defaultProcessingMode: ProcessingMode,
        announcementRequired: Bool = false,
        blockedDomains: [String] = [],
        blockedLocations: [String] = []
    ) {
        self.policyID = policyID
        self.workspaceID = workspaceID
        self.retentionDays = retentionDays
        self.defaultProcessingMode = defaultProcessingMode
        self.announcementRequired = announcementRequired
        self.blockedDomains = blockedDomains
        self.blockedLocations = blockedLocations
    }
}
