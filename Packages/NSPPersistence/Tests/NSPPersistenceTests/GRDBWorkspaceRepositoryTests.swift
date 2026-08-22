import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBWorkspaceRepository")
struct GRDBWorkspaceRepositoryTests {
    @Test func test_insertThenFind_roundTripsFieldsAndDerivesMembersFromPersonRows() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        let workspace = Workspace(workspaceID: WorkspaceID(rawValue: UUID()), name: "My Workspace")
        try await repository.insert(workspace, at: Date(timeIntervalSince1970: 1_700_000_000))

        let personID = PersonID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision)
                    VALUES (?, ?, 'Alex', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [personID.rawValue.uuidString, workspace.workspaceID.rawValue.uuidString])
        }

        let found = try await repository.find(workspace.workspaceID)
        #expect(found?.name == "My Workspace")
        #expect(found?.memberPersonIDs == [personID])
    }

    @Test func test_find_missingWorkspace_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)

        let found = try await repository.find(WorkspaceID(rawValue: UUID()))
        #expect(found == nil)
    }

    /// "The First Hour" wizard's identity step renames the placeholder
    /// "My Workspace" — `memberPersonIDs` must stay derived from `person`
    /// rows afterward, never overwritten as a stale snapshot from before
    /// the rename (2026-08-22).
    @Test func test_update_renamesTheWorkspaceAndKeepsDerivedMembersCurrent() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        var workspace = Workspace(workspaceID: WorkspaceID(rawValue: UUID()), name: "My Workspace")
        try await repository.insert(workspace, at: Date(timeIntervalSince1970: 1_700_000_000))

        let personID = PersonID(rawValue: UUID())
        let workspaceID = workspace.workspaceID
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision)
                    VALUES (?, ?, 'Dana Chen', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }

        workspace.name = "Acme Inc"
        try await repository.update(workspace, at: Date())

        let found = try await repository.find(workspace.workspaceID)
        #expect(found?.name == "Acme Inc")
        #expect(found?.memberPersonIDs == [personID])
    }

    @Test func test_update_missingWorkspace_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        let workspace = Workspace(workspaceID: WorkspaceID(rawValue: UUID()), name: "Ghost")
        await #expect(throws: PersistenceError.self) { try await repository.update(workspace, at: Date()) }
    }
}
