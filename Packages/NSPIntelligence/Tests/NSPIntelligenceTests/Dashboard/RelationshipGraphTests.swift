import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPIntelligence

/// "The Spine" recommendation's central read layer (`RelationshipGraph`,
/// NSP-166, 2026-08-22) had zero dedicated test coverage before this suite
/// — `MyWorkView`, `PersonDetailView`, and every future Thread/Project page
/// all depend on `everything(tiedToThread:)`/`tiedToPerson:`/`tiedToProject:`
/// being correct, so a bug here is silent everywhere at once. Uses the real
/// GRDB repositories against an in-memory `AppDatabase`, same pattern
/// `DashboardComposerThreadsTests` already established, since the behavior
/// under test is real joins (`thread_participant`, `meeting_thread`,
/// `project_person`) a fake can't exercise.
@Suite("RelationshipGraph")
struct RelationshipGraphTests {
    private struct Fixture {
        let workspaceID: WorkspaceID
        let policyID: PolicyID
        let creatorID: PersonID
    }

    private static func makeFixture(_ appDatabase: AppDatabase) async throws -> Fixture {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        let creatorID = PersonID(rawValue: UUID())
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
                arguments: [creatorID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }
        return Fixture(workspaceID: workspaceID, policyID: policyID, creatorID: creatorID)
    }

    private static func makeRepositories(_ appDatabase: AppDatabase) -> RelationshipRepositories {
        RelationshipRepositories(
            meeting: GRDBMeetingRepository(dbWriter: appDatabase.dbWriter),
            action: GRDBActionRepository(dbWriter: appDatabase.dbWriter),
            decision: GRDBDecisionRepository(dbWriter: appDatabase.dbWriter),
            thread: GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter),
            project: GRDBProjectRepository(dbWriter: appDatabase.dbWriter),
            meetingAttendee: GRDBMeetingAttendeeRepository(dbWriter: appDatabase.dbWriter),
            threadParticipant: GRDBThreadParticipantRepository(dbWriter: appDatabase.dbWriter),
            projectPerson: GRDBProjectPersonRepository(dbWriter: appDatabase.dbWriter))
    }

    /// Every join table this suite exercises (`thread_participant`,
    /// `project_person`, `meeting_attendee`) has a real foreign key to
    /// `person` — a bare random `PersonID` fails the insert rather than
    /// silently succeeding, so every person referenced anywhere below must
    /// be a real row first.
    @discardableResult
    private static func insertPerson(
        _ appDatabase: AppDatabase, workspaceID: WorkspaceID, name: String = "Someone"
    ) async throws -> PersonID {
        let person = Person(personID: PersonID(rawValue: UUID()), workspaceID: workspaceID, name: name)
        try await GRDBPersonRepository(dbWriter: appDatabase.dbWriter).insert(person, at: Date())
        return person.personID
    }

    private static func insertMeeting(
        _ appDatabase: AppDatabase, meetingID: MeetingID, workspaceID: WorkspaceID, policyID: PolicyID
    ) async throws {
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Weekly sync', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'savedRaw', ?, 'localOnly', 'complete', 0, '2026-01-01', '2026-01-01', 1
                    )
                    """,
                arguments: [meetingID.rawValue.uuidString, workspaceID.rawValue.uuidString, policyID.rawValue.uuidString])
        }
    }

    /// Exactly the query "The First Hour" wizard's Threads step depends on
    /// end to end: a Thread created in the wizard, a Person tagged onto it,
    /// and a meeting later joined to it — `everything(tiedToThread:)` must
    /// surface all three kinds together.
    @Test func test_tiedToThread_returnsMeetingsActionsDecisionsAndTaggedPeopleTogether() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Q3 board renewal",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await repositories.thread.insert(thread, at: now)

        let personID = try await Self.insertPerson(appDatabase, workspaceID: fixture.workspaceID, name: "Dana Chen")
        try await repositories.threadParticipant.setParticipants(for: thread.threadID, personIDs: [personID])

        let meetingID = MeetingID(rawValue: UUID())
        try await Self.insertMeeting(
            appDatabase, meetingID: meetingID, workspaceID: fixture.workspaceID, policyID: fixture.policyID)
        try await repositories.thread.setThreads(for: meetingID, threadIDs: [thread.threadID])

        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: meetingID,
            threadID: thread.threadID, text: "Send the recap", evidence: [], createdBy: fixture.creatorID)
        try await repositories.action.insert(action, at: now)

        let decision = Decision(
            decisionID: DecisionID(rawValue: UUID()), meetingID: meetingID, threadID: thread.threadID,
            text: "Renew for two years", evidence: [], createdBy: fixture.creatorID)
        try await repositories.decision.insert(decision, at: now)

        let bundle = try await RelationshipGraph.everything(tiedToThread: thread.threadID, repositories: repositories)

        #expect(bundle.meetings.map(\.meetingID) == [meetingID])
        #expect(bundle.actions.map(\.actionID) == [action.actionID])
        #expect(bundle.decisions.map(\.decisionID) == [decision.decisionID])
        #expect(bundle.personIDs == [personID])
    }

    /// A freestanding action (no meeting) tied to a thread must still show
    /// up — `everything` reads it through `thread.fetchMeetingIDs`'s
    /// per-meeting loop *and* nothing about a freestanding action requires
    /// a meeting to exist, so this specifically guards against a future
    /// refactor accidentally requiring one.
    @Test func test_tiedToPerson_findsFreestandingActionsByCounterpartyEvenWithNoMeeting() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let counterpartyID = try await Self.insertPerson(
            appDatabase, workspaceID: fixture.workspaceID, name: "Vendor Rep")
        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: nil,
            counterpartyID: counterpartyID, text: "Sign the vendor contract extension", evidence: [],
            createdBy: fixture.creatorID)
        try await repositories.action.insert(action, at: now)

        let bundle = try await RelationshipGraph.everything(tiedToPerson: counterpartyID, repositories: repositories)

        #expect(bundle.actions.map(\.actionID) == [action.actionID])
        #expect(bundle.meetings.isEmpty)
    }

    /// Duplicate detection: an action reachable both via its meeting *and*
    /// via `counterpartyID` must appear once, not twice — `dedupeActions`'s
    /// own reason for existing.
    @Test func test_tiedToPerson_dedupesAnActionReachableByBothMeetingAndCounterparty() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let attendeeID = try await Self.insertPerson(appDatabase, workspaceID: fixture.workspaceID, name: "Attendee")
        let meetingID = MeetingID(rawValue: UUID())
        try await Self.insertMeeting(
            appDatabase, meetingID: meetingID, workspaceID: fixture.workspaceID, policyID: fixture.policyID)
        try await repositories.meetingAttendee.setAttendees(for: meetingID, personIDs: [attendeeID])

        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, meetingID: meetingID,
            counterpartyID: attendeeID, text: "Send the recap", evidence: [], createdBy: fixture.creatorID)
        try await repositories.action.insert(action, at: now)

        let bundle = try await RelationshipGraph.everything(tiedToPerson: attendeeID, repositories: repositories)
        #expect(bundle.actions.map(\.actionID) == [action.actionID])
    }

    @Test func test_tiedToProject_returnsMeetingsAndTrackedPeople() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: fixture.workspaceID, name: "Engineering",
            createdAt: now, updatedAt: now)
        try await repositories.project.insert(project, at: now)

        let personID = try await Self.insertPerson(appDatabase, workspaceID: fixture.workspaceID, name: "Team Lead")
        try await repositories.projectPerson.setPeople(for: project.projectID, personIDs: [personID])

        let meetingID = MeetingID(rawValue: UUID())
        try await Self.insertMeeting(
            appDatabase, meetingID: meetingID, workspaceID: fixture.workspaceID, policyID: fixture.policyID)
        try await repositories.project.setProjects(for: meetingID, projectIDs: [project.projectID])

        let bundle = try await RelationshipGraph.everything(tiedToProject: project.projectID, repositories: repositories)

        #expect(bundle.meetings.map(\.meetingID) == [meetingID])
        #expect(bundle.personIDs == [personID])
    }

    @Test func test_tiedToThread_emptyThread_returnsAnEmptyBundleNotAnError() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Brand new",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await repositories.thread.insert(thread, at: now)

        let bundle = try await RelationshipGraph.everything(tiedToThread: thread.threadID, repositories: repositories)
        #expect(bundle.meetings.isEmpty)
        #expect(bundle.actions.isEmpty)
        #expect(bundle.personIDs.isEmpty)
    }
}
