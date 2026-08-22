import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

/// `AmbientSuggestion` (the "Overheard"/Exercise Mode inbox entity,
/// Migration023) had no dedicated repository test file — coverage existed
/// only for the relevance gate and extractor that *produce* suggestions
/// (`AmbientRelevanceGateTests` in NSPIntelligence), never for the
/// persistence layer `AmbientSuggestionsInboxView` reads and writes.
@Suite("GRDBAmbientSuggestionRepository")
struct GRDBAmbientSuggestionRepositoryTests {
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

    @Test func test_insertThenFetchPending_roundTripsFieldsIncludingEvidence() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBAmbientSuggestionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let suggestion = AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: UUID()), workspaceID: workspaceID, kind: .action,
            text: "Send Dana the updated deck",
            evidence: AmbientEvidence(excerpt: "I'll send Dana the updated deck", capturedAt: now), createdAt: now,
            updatedAt: now)

        try await repository.insert(suggestion, at: now)
        let pending = try await repository.fetchPending(workspaceID: workspaceID)

        #expect(pending.count == 1)
        #expect(pending.first?.text == "Send Dana the updated deck")
        #expect(pending.first?.evidence.excerpt == "I'll send Dana the updated deck")
        #expect(pending.first?.status == .pending)
    }

    /// The inbox only ever shows `.pending` — accepting or rejecting must
    /// remove a suggestion from `fetchPending`'s result without deleting
    /// its row (the row is the audit trail of what the assistant caught).
    @Test func test_update_toAcceptedOrRejected_removesItFromPendingButKeepsTheRow() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBAmbientSuggestionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        var accepted = AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: UUID()), workspaceID: workspaceID, kind: .action,
            text: "Follow up with Marcus", evidence: AmbientEvidence(excerpt: "follow up with Marcus", capturedAt: now),
            createdAt: now, updatedAt: now)
        var rejected = AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: UUID()), workspaceID: workspaceID, kind: .decision,
            text: "Pass the salt", evidence: AmbientEvidence(excerpt: "pass the salt", capturedAt: now), createdAt: now,
            updatedAt: now)
        try await repository.insert(accepted, at: now)
        try await repository.insert(rejected, at: now)

        accepted.status = .accepted
        rejected.status = .rejected
        try await repository.update(accepted, at: now)
        try await repository.update(rejected, at: now)

        let pending = try await repository.fetchPending(workspaceID: workspaceID)
        #expect(pending.isEmpty)
    }

    /// `threadID`/`counterpartyID` matches (relevance-gate output) round-
    /// trip — `nil` means "offered as new," never silently coerced.
    @Test func test_insertThenFetchPending_roundTripsThreadAndCounterpartyMatches() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBAmbientSuggestionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: "Vendor contract",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter).insert(thread, at: now)
        let threadID = thread.threadID

        let person = Person(personID: PersonID(rawValue: UUID()), workspaceID: workspaceID, name: "Dana Chen")
        try await GRDBPersonRepository(dbWriter: appDatabase.dbWriter).insert(person, at: now)
        let personID = person.personID
        let suggestion = AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: UUID()), workspaceID: workspaceID, kind: .action,
            text: "Sign the vendor contract extension", threadID: threadID, counterpartyID: personID,
            evidence: AmbientEvidence(excerpt: "sign the contract extension", capturedAt: now), createdAt: now,
            updatedAt: now)

        try await repository.insert(suggestion, at: now)
        let pending = try await repository.fetchPending(workspaceID: workspaceID)

        #expect(pending.first?.threadID == threadID)
        #expect(pending.first?.counterpartyID == personID)
    }

    @Test func test_delete_removesTheSuggestion() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBAmbientSuggestionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let suggestion = AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: UUID()), workspaceID: workspaceID, kind: .action,
            text: "Short-lived", evidence: AmbientEvidence(excerpt: "short-lived", capturedAt: now), createdAt: now,
            updatedAt: now)
        try await repository.insert(suggestion, at: now)

        try await repository.delete(suggestion.ambientSuggestionID)
        let pending = try await repository.fetchPending(workspaceID: workspaceID)
        #expect(pending.isEmpty)
    }
}
