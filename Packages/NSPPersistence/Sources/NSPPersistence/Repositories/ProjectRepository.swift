import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Project` plus the `meeting_project` many-to-many join (docs/09
/// Projects feature). Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol ProjectRepository: Sendable {
    func insert(_ project: Project, at date: Date) async throws
    func update(_ project: Project, at date: Date) async throws
    func find(_ id: ProjectID) async throws -> Project?
    func fetchAll(workspaceID: WorkspaceID) async throws -> [Project]
    func delete(_ id: ProjectID) async throws

    /// Full replace of `meetingID`'s project associations — same
    /// "delete-then-reinsert" pattern as `EmbeddingRepository.replaceAll`,
    /// so re-assigning a meeting's projects is a clean overwrite, never an
    /// accumulation. An empty set clears every association.
    func setProjects(for meetingID: MeetingID, projectIDs: Set<ProjectID>) async throws
    func fetchProjectIDs(for meetingID: MeetingID) async throws -> Set<ProjectID>
    func fetchMeetingIDs(for projectID: ProjectID) async throws -> Set<MeetingID>
}

public struct GRDBProjectRepository: ProjectRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ project: Project, at date: Date) async throws {
        let row = ProjectRow(project: project, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ project: Project, at date: Date) async throws {
        let id = project.projectID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try ProjectRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: ProjectRow.databaseTableName, key: id)
            }
            let updated = ProjectRow(
                project: project, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: ProjectID) async throws -> Project? {
        try await dbWriter.read { db in
            try ProjectRow.fetchOne(db, key: id.rawValue.uuidString)?.asDomain()
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [Project] {
        try await dbWriter.read { db in
            try ProjectRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .order(Column("name"))
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }

    public func delete(_ id: ProjectID) async throws {
        try await dbWriter.write { db in
            _ = try ProjectRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    public func setProjects(for meetingID: MeetingID, projectIDs: Set<ProjectID>) async throws {
        let meetingIDString = meetingID.rawValue.uuidString
        try await dbWriter.write { db in
            try MeetingProjectRow.filter(Column("meeting_id") == meetingIDString).deleteAll(db)
            for projectID in projectIDs {
                try MeetingProjectRow(meetingID: meetingIDString, projectID: projectID.rawValue.uuidString).insert(db)
            }
        }
    }

    public func fetchProjectIDs(for meetingID: MeetingID) async throws -> Set<ProjectID> {
        let meetingIDString = meetingID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingProjectRow.filter(Column("meeting_id") == meetingIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.projectID) }.map { ProjectID(rawValue: $0) })
        }
    }

    public func fetchMeetingIDs(for projectID: ProjectID) async throws -> Set<MeetingID> {
        let projectIDString = projectID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingProjectRow.filter(Column("project_id") == projectIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.meetingID) }.map { MeetingID(rawValue: $0) })
        }
    }
}
