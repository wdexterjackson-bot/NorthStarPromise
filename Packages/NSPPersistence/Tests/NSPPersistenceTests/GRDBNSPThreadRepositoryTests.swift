import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

/// `NSPThread` had no dedicated repository test file before "The First
/// Hour" wizard (2026-08-22) — coverage existed only indirectly through
/// `DashboardComposerThreadsTests`'s join-table assertions. This suite
/// covers the repository's own CRUD surface, which the wizard's Threads
/// step (`GettingStartedCoordinator`) depends on directly.
@Suite("GRDBNSPThreadRepository")
struct GRDBNSPThreadRepositoryTests {
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

    @Test func test_insertThenFind_roundTripsFieldsIncludingKindAndColorSlot() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: "Q3 board renewal",
            threadDescription: "Renewal terms + budget", kind: .deal, lastTouchedAt: now, createdAt: now,
            updatedAt: now)

        try await repository.insert(thread, at: now)
        let found = try await repository.find(thread.threadID)

        #expect(found?.title == "Q3 board renewal")
        #expect(found?.kind == .deal)
        #expect(found?.colorSlot == thread.colorSlot)
    }

    /// `ThreadKind.household` (Ambient Mode Phase 2) round-trips like every
    /// other case — the wizard's kind picker offers it alongside work
    /// kinds.
    @Test func test_insertThenFind_householdKindRoundTrips() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: "Home", kind: .household,
            lastTouchedAt: now, createdAt: now, updatedAt: now)

        try await repository.insert(thread, at: now)
        let found = try await repository.find(thread.threadID)
        #expect(found?.kind == .household)
    }

    @Test func test_fetchAll_scopesToWorkspaceAndOrdersConsistently() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let otherWorkspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()

        let mine = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: "Mine", lastTouchedAt: now,
            createdAt: now, updatedAt: now)
        let notMine = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: otherWorkspaceID, title: "Not mine",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await repository.insert(mine, at: now)
        try await repository.insert(notMine, at: now)

        let all = try await repository.fetchAll(workspaceID: workspaceID)
        #expect(all.map(\.threadID) == [mine.threadID])
    }

    @Test func test_delete_removesTheThread() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: "Short-lived",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await repository.insert(thread, at: now)

        try await repository.delete(thread.threadID)
        #expect(try await repository.find(thread.threadID) == nil)
    }

    @Test func test_find_missingThread_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(NSPThreadID(rawValue: UUID())) == nil)
    }
}
