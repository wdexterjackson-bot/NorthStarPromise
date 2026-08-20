import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBAuditEventRepository")
struct GRDBAuditEventRepositoryTests {
    @Test func test_insertThenFind_roundTripsAllFieldsWithNoActor() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBAuditEventRepository(dbWriter: appDatabase.dbWriter)

        let event = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()), actorID: nil, action: "egress.authorize",
            object: "meeting:test", payloadHash: "abc123", result: .success,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        try await repository.insert(event, at: Date())
        let found = try await repository.find(event.auditEventID)

        #expect(found == event)
    }

    @Test func test_insertThenFind_roundTripsWithAnActor() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = WorkspaceID(rawValue: UUID())
        let personID = PersonID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, 'Workspace', '2026-01-01', '2026-01-01', 1)",
                arguments: [workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision)
                    VALUES (?, ?, 'Author', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }
        let repository = GRDBAuditEventRepository(dbWriter: appDatabase.dbWriter)

        let event = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()), actorID: personID, action: "egress.revokeAll",
            object: "meeting:test:reason:userRequested:grants:1", payloadHash: "", result: .denied,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100))
        try await repository.insert(event, at: Date())

        #expect(try await repository.find(event.auditEventID) == event)
    }

    @Test func test_find_missingEvent_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBAuditEventRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(AuditEventID(rawValue: UUID())) == nil)
    }
}
