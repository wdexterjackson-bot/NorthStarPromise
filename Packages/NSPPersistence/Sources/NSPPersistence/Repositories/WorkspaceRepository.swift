import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Workspace`. Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol WorkspaceRepository: Sendable {
    func insert(_ workspace: Workspace, at date: Date) async throws
    /// Renames the workspace — added for "The First Hour" wizard's
    /// identity step (2026-08-22); `memberPersonIDs` is never written
    /// here, since it's always derived from `person.workspace_id`
    /// (`find`'s own doc comment), not a real stored column.
    func update(_ workspace: Workspace, at date: Date) async throws
    func find(_ id: WorkspaceID) async throws -> Workspace?
}

public struct GRDBWorkspaceRepository: WorkspaceRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ workspace: Workspace, at date: Date) async throws {
        let row = WorkspaceRow(workspace: workspace, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ workspace: Workspace, at date: Date) async throws {
        let id = workspace.workspaceID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try WorkspaceRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: WorkspaceRow.databaseTableName, key: id)
            }
            let updated = WorkspaceRow(
                workspace: workspace, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: WorkspaceID) async throws -> Workspace? {
        try await dbWriter.read { db in
            guard let row = try WorkspaceRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            let memberIDs =
                try String
                .fetchAll(db, sql: "SELECT person_id FROM person WHERE workspace_id = ?", arguments: [row.workspaceID])
                .compactMap { UUID(uuidString: $0) }
                .map { PersonID(rawValue: $0) }
            return try row.asDomain(memberPersonIDs: memberIDs)
        }
    }
}
