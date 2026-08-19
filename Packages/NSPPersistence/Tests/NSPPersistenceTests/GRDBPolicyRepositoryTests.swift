import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBPolicyRepository")
struct GRDBPolicyRepositoryTests {
    private static func makeWorkspace(_ appDatabase: AppDatabase) async throws -> WorkspaceID {
        let workspaceID = WorkspaceID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, 'Workspace', '2026-01-01', '2026-01-01', 1)",
                arguments: [workspaceID.rawValue.uuidString])
        }
        return workspaceID
    }

    @Test func test_insertThenFind_roundTripsAllFieldsIncludingBlockedLists() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBPolicyRepository(dbWriter: appDatabase.dbWriter)

        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()),
            workspaceID: workspaceID,
            retentionDays: 30,
            defaultProcessingMode: .onDevicePreferred,
            announcementRequired: true,
            blockedDomains: ["competitor.com", "external.example"],
            blockedLocations: ["conference-room-3"]
        )

        try await repository.insert(policy, at: Date())
        let found = try await repository.find(policy.policyID)

        #expect(found == policy)
    }

    @Test func test_update_replacesBlockedListsRatherThanAccumulating() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBPolicyRepository(dbWriter: appDatabase.dbWriter)

        var policy = Policy(
            policyID: PolicyID(rawValue: UUID()),
            workspaceID: workspaceID,
            defaultProcessingMode: .cloudAllowed,
            blockedDomains: ["a.example"]
        )
        try await repository.insert(policy, at: Date())

        policy.blockedDomains = []
        policy.defaultProcessingMode = .localOnly
        try await repository.update(policy, at: Date())

        let found = try await repository.find(policy.policyID)
        #expect(found?.blockedDomains == [])
        #expect(found?.defaultProcessingMode == .localOnly)
    }

    @Test func test_find_missingPolicy_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBPolicyRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(PolicyID(rawValue: UUID())) == nil)
    }
}
