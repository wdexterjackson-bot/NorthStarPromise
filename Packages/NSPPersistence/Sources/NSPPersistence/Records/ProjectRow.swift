import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `project` table (`Migration005AddProjects`).
struct ProjectRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"

    var projectID: String
    var workspaceID: String
    var name: String
    var description: String?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case workspaceID = "workspace_id"
        case name
        case description
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(project: Project, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.projectID = project.projectID.rawValue.uuidString
        self.workspaceID = project.workspaceID.rawValue.uuidString
        self.name = project.name
        self.description = project.projectDescription
        self.archivedAt = project.archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> Project {
        guard let projectUUID = UUID(uuidString: projectID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "project_id", value: projectID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        return Project(
            projectID: ProjectID(rawValue: projectUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID),
            name: name, projectDescription: description, archivedAt: archivedAt, createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

/// Mirrors one row of the `meeting_project` join table.
struct MeetingProjectRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_project"

    var meetingID: String
    var projectID: String

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case projectID = "project_id"
    }
}
