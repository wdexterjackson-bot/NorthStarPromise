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
}
