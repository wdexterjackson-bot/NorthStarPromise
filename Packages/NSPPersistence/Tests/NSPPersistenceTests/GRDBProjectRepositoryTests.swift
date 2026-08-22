import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

/// `Project` had no dedicated repository test file before "The First Hour"
/// wizard (2026-08-22) — its calendar step (`WizardCalendarStep`) creates
/// real `Project` rows from a user-confirmed group of calendar events, so
/// this repository's own CRUD surface is now directly load-bearing for a
/// setup flow, not just `MeetingTitlePromptView`'s project picker.
@Suite("GRDBProjectRepository")
struct GRDBProjectRepositoryTests {
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

    @Test func test_insertThenFind_roundTripsFields() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBProjectRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID, name: "Engineering",
            projectDescription: "Weekly eng sync series", createdAt: now, updatedAt: now)

        try await repository.insert(project, at: now)
        let found = try await repository.find(project.projectID)

        #expect(found == project)
    }

    @Test func test_fetchAll_scopesToWorkspace() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let otherWorkspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBProjectRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()

        let mine = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID, name: "Mine", createdAt: now,
            updatedAt: now)
        let notMine = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: otherWorkspaceID, name: "Not mine", createdAt: now,
            updatedAt: now)
        try await repository.insert(mine, at: now)
        try await repository.insert(notMine, at: now)

        let all = try await repository.fetchAll(workspaceID: workspaceID)
        #expect(all.map(\.projectID) == [mine.projectID])
    }

    /// A meeting created later (once the executive actually records
    /// something under this project) joins it through this exact call —
    /// the same one `MeetingTitlePromptView`'s project picker uses.
    @Test func test_setProjects_thenFetchMeetingIDs_roundTripsTheJoin() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBProjectRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID, name: "Engineering", createdAt: now,
            updatedAt: now)
        try await repository.insert(project, at: now)

        let meetingID = MeetingID(rawValue: UUID())
        let policyID = UUID()
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """, arguments: [policyID.uuidString, workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Eng sync', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'savedRaw', ?, 'localOnly', 'complete', 0, '2026-01-01', '2026-01-01', 1
                    )
                    """,
                arguments: [meetingID.rawValue.uuidString, workspaceID.rawValue.uuidString, policyID.uuidString])
        }

        try await repository.setProjects(for: meetingID, projectIDs: [project.projectID])

        let projectIDs = try await repository.fetchProjectIDs(for: meetingID)
        #expect(projectIDs == [project.projectID])
        let meetingIDs = try await repository.fetchMeetingIDs(for: project.projectID)
        #expect(meetingIDs == [meetingID])
    }

    @Test func test_delete_removesTheProject() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let workspaceID = try await Self.makeWorkspace(appDatabase)
        let repository = GRDBProjectRepository(dbWriter: appDatabase.dbWriter)
        let now = Date()
        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID, name: "Short-lived", createdAt: now,
            updatedAt: now)
        try await repository.insert(project, at: now)

        try await repository.delete(project.projectID)
        #expect(try await repository.find(project.projectID) == nil)
    }
}
