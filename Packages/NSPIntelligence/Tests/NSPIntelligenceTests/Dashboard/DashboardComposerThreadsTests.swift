import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPIntelligence

/// Phase C's own stated verification: a freestanding `Action` (no meeting)
/// surfaces in `DashboardComposer`'s `needsYou`, and a `Meeting` can join
/// two threads at once (docs/09-BACKLOG.md, "rescoping the
/// meeting-organization data model"). Uses the real GRDB repositories
/// against an in-memory `AppDatabase` rather than fakes — the behavior
/// under test is the `meeting_thread` join and `action_item.workspace_id`
/// columns actually round-tripping, which a fake can't exercise.
@Suite("DashboardComposer — freestanding actions and multi-thread meetings")
struct DashboardComposerThreadsTests {
    private struct Fixture {
        let workspaceID: WorkspaceID
        let policyID: PolicyID
        let personID: PersonID
        let meetingID: MeetingID
    }

    private static func makeFixture(_ appDatabase: AppDatabase) async throws -> Fixture {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        let personID = PersonID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
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
            try db.execute(
                sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, ?, 'You', '2026-01-01', '2026-01-01', 1)",
                arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Weekly product sync', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'savedRaw', ?, 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """,
                arguments: [
                    meetingID.rawValue.uuidString, workspaceID.rawValue.uuidString, policyID.rawValue.uuidString,
                ])
        }
        return Fixture(workspaceID: workspaceID, policyID: policyID, personID: personID, meetingID: meetingID)
    }

    @Test func test_freestandingAction_hasNoMeetingButKeepsItsWorkspaceThreadAndCounterparty() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let threadRepository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let actionRepository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Vendor contract",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await threadRepository.insert(thread, at: now)

        let counterpartyID = PersonID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES (?, ?, 'Vendor Rep', '2026-01-01', '2026-01-01', 1)",
                arguments: [counterpartyID.rawValue.uuidString, fixture.workspaceID.rawValue.uuidString])
        }
        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: nil,
            threadID: thread.threadID, counterpartyID: counterpartyID, text: "Sign the vendor contract extension",
            direction: .iOwe, evidence: [], createdBy: fixture.personID)
        try await actionRepository.insert(action, at: now)

        let found = try #require(try await actionRepository.find(action.actionID))
        #expect(found.meetingID == nil)
        #expect(found.threadID == thread.threadID)
        #expect(found.counterpartyID == counterpartyID)

        // The workspace-wide fetch — what `DashboardComposer`'s `needsYou`
        // reads from — still finds it despite having no meeting.
        let workspaceActions = try await actionRepository.fetchAll(workspaceID: fixture.workspaceID)
        #expect(workspaceActions.map(\.actionID).contains(action.actionID))

        // A per-person query (what a future People-view "what do I owe
        // this person" filter would run) is a real, direct query now —
        // not a guess from meeting attendees.
        let owedToCounterparty = workspaceActions.filter { $0.counterpartyID == counterpartyID }
        #expect(owedToCounterparty.map(\.actionID) == [action.actionID])
    }

    @Test func test_meeting_joinsTwoThreadsSimultaneously() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let threadRepository = GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter)
        let meetingRepository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let firstThread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Vendor contract",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        let secondThread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Q3 roadmap",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await threadRepository.insert(firstThread, at: now)
        try await threadRepository.insert(secondThread, at: now)

        try await threadRepository.setThreads(
            for: fixture.meetingID, threadIDs: [firstThread.threadID, secondThread.threadID])

        let threadIDs = try await threadRepository.fetchThreadIDs(for: fixture.meetingID)
        #expect(threadIDs == [firstThread.threadID, secondThread.threadID])

        let firstThreadMeetings = try await meetingRepository.fetchAll(threadID: firstThread.threadID)
        let secondThreadMeetings = try await meetingRepository.fetchAll(threadID: secondThread.threadID)
        #expect(firstThreadMeetings.map(\.meetingID) == [fixture.meetingID])
        #expect(secondThreadMeetings.map(\.meetingID) == [fixture.meetingID])

        let byThread = try await threadRepository.fetchMeetingIDsByThread(workspaceID: fixture.workspaceID)
        #expect(byThread[firstThread.threadID] == [fixture.meetingID])
        #expect(byThread[secondThread.threadID] == [fixture.meetingID])
    }

    @Test func test_compose_needsYou_includesAFreestandingActionAlongsideMeetingTiedOnes() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let actionRepository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let meetingTiedAction = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: fixture.meetingID,
            text: "Send the recap", direction: .iOwe, evidence: [], createdBy: fixture.personID)
        let freestandingAction = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: nil,
            text: "Sign the vendor contract extension", direction: .iOwe, evidence: [], createdBy: fixture.personID)
        try await actionRepository.insert(meetingTiedAction, at: now)
        try await actionRepository.insert(freestandingAction, at: now)

        let repositories = DashboardRepositories(
            meeting: GRDBMeetingRepository(dbWriter: appDatabase.dbWriter), action: actionRepository,
            decision: GRDBDecisionRepository(dbWriter: appDatabase.dbWriter),
            thread: GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter))
        let model = try await DashboardComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())

        let needsYouIDs = Set(model.needsYou.items.map(\.actionID))
        #expect(needsYouIDs.isSuperset(of: [meetingTiedAction.actionID, freestandingAction.actionID]))
        let freestandingItem = try #require(model.needsYou.items.first { $0.actionID == freestandingAction.actionID })
        #expect(freestandingItem.provenance == "")
    }
}
