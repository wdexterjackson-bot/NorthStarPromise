import Foundation

/// A grouping of meetings around one initiative — how the app answers
/// "what's open across everything tied to this project," not a new capture
/// concept of its own. A meeting belongs to at most one project
/// (`MeetingTitlePromptView`'s single-select project picker). A `BrainDump`
/// is never itself linked to a project this way — its individual extracted
/// action items/decisions can each join one once that distribution feature
/// exists (docs/09-BACKLOG.md, `NSP-154`), but the Brain Dump as a whole
/// doesn't. `ProjectRepository.setProjects` is the many-to-many join a
/// `Meeting`/project relationship uses under the hood even though today's
/// UI only ever sets one.
public struct Project: Sendable, Hashable, Codable, Identifiable {
    public let projectID: ProjectID
    public var id: ProjectID { projectID }
    public let workspaceID: WorkspaceID

    public var name: String
    public var projectDescription: String?
    public var archivedAt: Date?

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        projectID: ProjectID,
        workspaceID: WorkspaceID,
        name: String,
        projectDescription: String? = nil,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.projectID = projectID
        self.workspaceID = workspaceID
        self.name = name
        self.projectDescription = projectDescription
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
