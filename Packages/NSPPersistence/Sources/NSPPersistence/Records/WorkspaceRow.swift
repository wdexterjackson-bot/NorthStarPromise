import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `workspace` table (docs/02 §5). `Workspace.memberPersonIDs`
/// isn't a stored column here — `person` rows already carry a `workspace_id`
/// foreign key, so the member list is derived by querying that table
/// rather than duplicated redundantly (`WorkspaceRepository` owns that
/// join, the same "row owns its own columns" split used everywhere else).
struct WorkspaceRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workspace"

    var workspaceID: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(workspace: Workspace, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.workspaceID = workspace.workspaceID.rawValue.uuidString
        self.name = workspace.name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(memberPersonIDs: [PersonID]) throws -> Workspace {
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        return Workspace(
            workspaceID: WorkspaceID(rawValue: workspaceUUID), name: name, memberPersonIDs: memberPersonIDs)
    }
}
