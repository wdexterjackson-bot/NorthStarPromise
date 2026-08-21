import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBScheduledRecordingRepository")
struct GRDBScheduledRecordingRepositoryTests {
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

    private static func makeItem(
        workspaceID: WorkspaceID, status: ScheduledRecordingStatus = .pending,
        alertStyle: ScheduledRecordingAlertStyle = .sound, start: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ScheduledRecording {
        ScheduledRecording(
            scheduledRecordingID: .generate(clock: SystemClock()), workspaceID: workspaceID, title: "Weekly sync",
            scheduledStart: start, scheduledStop: start.addingTimeInterval(1800), status: status,
            alertStyle: alertStyle, createdAt: start, updatedAt: start)
    }

    @Test func test_insertThenFind_roundTripsAllFields() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        let item = Self.makeItem(workspaceID: workspaceID, alertStyle: .vibrateOnly)

        try await repository.insert(item, at: item.createdAt)
        let found = try await repository.find(item.scheduledRecordingID)

        #expect(found == item)
    }

    @Test func test_update_missingRow_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        let item = Self.makeItem(workspaceID: workspaceID)

        await #expect(throws: PersistenceError.self) { try await repository.update(item, at: Date()) }
    }

    @Test func test_update_changesStatusAndBumpsRevisionWithoutTouchingCreatedAt() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        var item = Self.makeItem(workspaceID: workspaceID)
        try await repository.insert(item, at: Date(timeIntervalSince1970: 1))

        item.status = .started
        try await repository.update(item, at: Date(timeIntervalSince1970: 2))

        let found = try await repository.find(item.scheduledRecordingID)
        #expect(found?.status == .started)
        #expect(found?.createdAt == Date(timeIntervalSince1970: 1))
        #expect(found?.updatedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func test_fetchPending_returnsOnlyPendingAndNotified() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        let pending = Self.makeItem(workspaceID: workspaceID, status: .pending)
        let notified = Self.makeItem(workspaceID: workspaceID, status: .notified)
        let started = Self.makeItem(workspaceID: workspaceID, status: .started)
        let completed = Self.makeItem(workspaceID: workspaceID, status: .completed)
        for item in [pending, notified, started, completed] {
            try await repository.insert(item, at: Date())
        }

        let result = try await repository.fetchPending(workspaceID: workspaceID)

        #expect(
            Set(result.map(\.scheduledRecordingID))
                == Set([pending.scheduledRecordingID, notified.scheduledRecordingID]))
    }

    @Test func test_fetchAll_ordersByScheduledStart() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        let later = Self.makeItem(workspaceID: workspaceID, start: Date(timeIntervalSince1970: 2_000_000_000))
        let earlier = Self.makeItem(workspaceID: workspaceID, start: Date(timeIntervalSince1970: 1_000_000_000))
        try await repository.insert(later, at: Date())
        try await repository.insert(earlier, at: Date())

        let all = try await repository.fetchAll(workspaceID: workspaceID)

        #expect(all.map(\.scheduledRecordingID) == [earlier.scheduledRecordingID, later.scheduledRecordingID])
    }

    @Test func test_delete_removesTheRow() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBScheduledRecordingRepository(dbWriter: appDatabase.dbWriter)
        let item = Self.makeItem(workspaceID: workspaceID)
        try await repository.insert(item, at: Date())

        try await repository.delete(item.scheduledRecordingID)

        let found = try await repository.find(item.scheduledRecordingID)
        #expect(found == nil)
    }
}
