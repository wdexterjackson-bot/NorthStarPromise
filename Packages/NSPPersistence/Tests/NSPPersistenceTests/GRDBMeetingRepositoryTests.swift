import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBMeetingRepository")
struct GRDBMeetingRepositoryTests {
    private static func makeWorkspaceAndPolicy(_ appDatabase: AppDatabase) async throws -> (WorkspaceID, PolicyID) {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, 'Workspace', '2026-01-01', '2026-01-01', 1)",
                arguments: [workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES (?, ?, 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """, arguments: [policyID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }
        return (workspaceID, policyID)
    }

    private static func makeMeeting(workspaceID: WorkspaceID, policyID: PolicyID) -> Meeting {
        Meeting(
            meetingID: MeetingID(rawValue: UUID()),
            workspaceID: workspaceID,
            title: "Weekly sync",
            captureMode: .watch,
            originDeviceID: DeviceID(rawValue: UUID()),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lifecycleState: .ready,
            policyID: policyID,
            processingMode: .localOnly,
            availability: .complete,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func test_insertThenFind_roundTripsAllFields() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let repository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        let meeting = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)

        try await repository.insert(meeting, at: meeting.createdAt)
        let found = try await repository.find(meeting.meetingID)

        #expect(found == meeting)
    }

    @Test func test_failedLifecycleState_roundTripsItsReason() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let repository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        var meeting = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        meeting.lifecycleState = .failed(reason: "microphone unavailable")

        try await repository.insert(meeting, at: meeting.createdAt)
        let found = try await repository.find(meeting.meetingID)

        #expect(found?.lifecycleState == .failed(reason: "microphone unavailable"))
    }

    @Test func test_partialAvailability_roundTripsMissingSegments() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let repository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        var meeting = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        let missing = [
            SegmentRef(segmentID: SegmentID(rawValue: UUID()), deviceID: DeviceID(rawValue: UUID()), sequence: 3),
            SegmentRef(segmentID: SegmentID(rawValue: UUID()), deviceID: DeviceID(rawValue: UUID()), sequence: 4),
        ]
        meeting.availability = .partial(missing: missing)

        try await repository.insert(meeting, at: meeting.createdAt)
        let found = try await repository.find(meeting.meetingID)

        guard case .partial(let foundMissing) = found?.availability else {
            Issue.record("expected .partial availability")
            return
        }
        #expect(Set(foundMissing) == Set(missing))
    }

    @Test func test_update_replacesMissingSegmentsRatherThanAccumulating() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let repository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        var meeting = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        let firstMissing = SegmentRef(
            segmentID: SegmentID(rawValue: UUID()), deviceID: DeviceID(rawValue: UUID()), sequence: 1)
        meeting.availability = .partial(missing: [firstMissing])
        try await repository.insert(meeting, at: meeting.createdAt)

        meeting.availability = .complete
        try await repository.update(meeting, at: Date(timeIntervalSince1970: 1_700_000_100))

        let found = try await repository.find(meeting.meetingID)
        #expect(found?.availability == .complete)

        let meetingIDString = meeting.meetingID.rawValue.uuidString
        let remainingRows = try await appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meeting_missing_segment WHERE meeting_id = ?",
                arguments: [meetingIDString])
        }
        #expect(remainingRows == 0)
    }

    @Test func test_fetchAll_excludesSoftDeletedByDefault() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let repository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)

        let active = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        try await repository.insert(active, at: active.createdAt)

        var deleted = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        deleted.deletedAt = Date(timeIntervalSince1970: 1_700_000_050)
        try await repository.insert(deleted, at: deleted.createdAt)

        let visible = try await repository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
        #expect(visible.map(\.meetingID) == [active.meetingID])

        let all = try await repository.fetchAll(workspaceID: workspaceID, includeDeleted: true)
        #expect(Set(all.map(\.meetingID)) == Set([active.meetingID, deleted.meetingID]))
    }

    /// The real proof behind `MeetingRepository.delete`'s doc comment: every
    /// `meeting_id` foreign key declares `ON DELETE CASCADE` and
    /// `AppDatabase` enables foreign-key enforcement, so deleting the
    /// `meeting` row alone must remove its actions too — no per-table
    /// cleanup code to trust or forget.
    @Test func test_delete_removesTheMeetingAndCascadesToItsActions() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let (workspaceID, policyID) = try await Self.makeWorkspaceAndPolicy(appDatabase)
        let personID = PersonID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, ?, 'You', '2026-01-01', '2026-01-01', 1)",
                arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }

        let meetingRepository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        let meeting = Self.makeMeeting(workspaceID: workspaceID, policyID: policyID)
        try await meetingRepository.insert(meeting, at: meeting.createdAt)

        let actionRepository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: workspaceID, meetingID: meeting.meetingID,
            text: "Follow up", evidence: [], createdBy: personID)
        try await actionRepository.insert(action, at: meeting.createdAt)

        try await meetingRepository.delete(meeting.meetingID)

        let foundMeeting = try await meetingRepository.find(meeting.meetingID)
        #expect(foundMeeting == nil)
        let remainingActions = try await appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM action_item WHERE meeting_id = ?",
                arguments: [meeting.meetingID.rawValue.uuidString])
        }
        #expect(remainingActions == 0)
    }
}
