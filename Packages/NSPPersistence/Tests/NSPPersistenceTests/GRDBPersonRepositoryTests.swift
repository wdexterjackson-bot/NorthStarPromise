import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBPersonRepository")
struct GRDBPersonRepositoryTests {
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

    @Test func test_insertThenFind_roundTripsFieldsAndAliasesInOrder() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBPersonRepository(dbWriter: appDatabase.dbWriter)
        let person = Person(
            personID: PersonID(rawValue: UUID()), workspaceID: workspaceID, name: "Alex",
            aliases: ["A. Rivera", "Al"], voiceEnrollmentRef: "voice-1", contactLink: "mailto:alex@example.com")

        try await repository.insert(person, at: Date(timeIntervalSince1970: 1_700_000_000))
        let found = try await repository.find(person.personID)

        #expect(found == person)
    }

    @Test func test_find_missingPerson_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBPersonRepository(dbWriter: appDatabase.dbWriter)

        let found = try await repository.find(PersonID(rawValue: UUID()))
        #expect(found == nil)
    }
}
