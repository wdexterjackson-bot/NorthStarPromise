/// A collaboration scope that determines the CloudKit zone and access
/// boundary for its meetings (docs/02 §2, §6).
public struct Workspace: Sendable, Hashable, Codable, Identifiable {
    public let workspaceID: WorkspaceID
    public var id: WorkspaceID { workspaceID }
    public var name: String
    public var memberPersonIDs: [PersonID]

    public init(workspaceID: WorkspaceID, name: String, memberPersonIDs: [PersonID] = []) {
        self.workspaceID = workspaceID
        self.name = name
        self.memberPersonIDs = memberPersonIDs
    }
}
