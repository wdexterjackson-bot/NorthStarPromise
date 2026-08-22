import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPIntelligence

/// "The Spine"'s flagship recommendation (`WeeklyBriefComposer`, NSP-169,
/// 2026-08-22) had zero dedicated test coverage before this suite — every
/// workspace gets this brief by default (`WeeklyBriefScheduler` registers
/// its Monday 8am notification unconditionally), so a bug in what it
/// surfaces reaches every user, every week, silently. Same real-GRDB
/// pattern as `RelationshipGraphTests`.
@Suite("WeeklyBriefComposer")
struct WeeklyBriefComposerTests {
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

    private static func makeRepositories(_ appDatabase: AppDatabase) -> WeeklyBriefRepositories {
        WeeklyBriefRepositories(
            meeting: GRDBMeetingRepository(dbWriter: appDatabase.dbWriter),
            action: GRDBActionRepository(dbWriter: appDatabase.dbWriter),
            decision: GRDBDecisionRepository(dbWriter: appDatabase.dbWriter),
            thread: GRDBNSPThreadRepository(dbWriter: appDatabase.dbWriter),
            person: GRDBPersonRepository(dbWriter: appDatabase.dbWriter))
    }

    @Test func test_compose_flagsA14PlusDayQuietThreadButNotARecentOne() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date()

        let quiet = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Vendor contract",
            lastTouchedAt: now.addingTimeInterval(-20 * 86400), createdAt: now, updatedAt: now)
        let active = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Q3 roadmap",
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        try await repositories.thread.insert(quiet, at: now)
        try await repositories.thread.insert(active, at: now)

        let brief = try await WeeklyBriefComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())

        #expect(brief.quietThreads.map(\.threadID) == [quiet.threadID])
        #expect(brief.quietThreads.first?.quietDays ?? 0 >= 14)
    }

    /// A `.closed` thread is never a "gone quiet" signal — closing it was
    /// the intended end state, not neglect.
    @Test func test_compose_neverFlagsAClosedThreadAsQuiet() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date()

        let closed = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: fixture.workspaceID, title: "Done deal",
            status: .closed, lastTouchedAt: now.addingTimeInterval(-40 * 86400), createdAt: now, updatedAt: now)
        try await repositories.thread.insert(closed, at: now)

        let brief = try await WeeklyBriefComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())
        #expect(brief.quietThreads.isEmpty)
    }

    /// "People waiting on you": an open, `.iOwe` action more than 7 days
    /// past its due date, grouped and named by counterparty — the exact
    /// query My Work / Weekly Brief's card renders.
    @Test func test_compose_overdueFollowUps_groupsByCounterpartyAndResolvesTheirName() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date()

        let counterparty = Person(
            personID: PersonID(rawValue: UUID()), workspaceID: fixture.workspaceID, name: "Marcus Webb")
        try await repositories.person.insert(counterparty, at: now)

        let overdueDate = now.addingTimeInterval(-9 * 86400)
        let firstOverdue = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, counterpartyID: counterparty.personID,
            text: "Send the recap", date: .explicit(overdueDate), direction: .iOwe, evidence: [],
            createdBy: fixture.creatorID)
        let secondOverdue = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, counterpartyID: counterparty.personID,
            text: "Follow up on pricing", date: .explicit(overdueDate), direction: .iOwe, evidence: [],
            createdBy: fixture.creatorID)
        let notYetOverdue = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, counterpartyID: counterparty.personID,
            text: "Not due yet", date: .explicit(now.addingTimeInterval(-2 * 86400)), direction: .iOwe, evidence: [],
            createdBy: fixture.creatorID)
        let theyOweMe = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: fixture.workspaceID, counterpartyID: counterparty.personID,
            text: "Their turn", date: .explicit(overdueDate), direction: .theyOwe, evidence: [],
            createdBy: fixture.creatorID)
        try await repositories.action.insert(firstOverdue, at: now)
        try await repositories.action.insert(secondOverdue, at: now)
        try await repositories.action.insert(notYetOverdue, at: now)
        try await repositories.action.insert(theyOweMe, at: now)

        let brief = try await WeeklyBriefComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())

        #expect(brief.overdueFollowUps.count == 1)
        let entry = try #require(brief.overdueFollowUps.first)
        #expect(entry.personName == "Marcus Webb")
        #expect(entry.openCount == 2)
    }

    /// A decision made in the trailing 7 days shows up; older decisions and
    /// decisions from a meeting outside that window do not.
    @Test func test_compose_decisionsLastWeek_scopesToTheTrailingSevenDaysByMeetingDate() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)
        let now = Date()

        let recentMeetingID = MeetingID(rawValue: UUID())
        let oldMeetingID = MeetingID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            for (meetingID, startedAt) in [
                (recentMeetingID, now.addingTimeInterval(-2 * 86400)), (oldMeetingID, now.addingTimeInterval(-30 * 86400)),
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO meeting (
                            meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                            started_at, lifecycle_state, policy_id, processing_mode, availability,
                            excluded_from_memory, created_at, updated_at, row_revision
                        ) VALUES (
                            ?, ?, 'Sync', 0, 'phone', 'AAAAAAAA-0000-7000-8000-000000000001',
                            ?, 'savedRaw', ?, 'localOnly', 'complete', 0, '2026-01-01', '2026-01-01', 1
                        )
                        """,
                    arguments: [
                        meetingID.rawValue.uuidString, fixture.workspaceID.rawValue.uuidString, startedAt,
                        fixture.policyID.rawValue.uuidString,
                    ])
            }
        }

        let recentDecision = Decision(
            decisionID: DecisionID(rawValue: UUID()), meetingID: recentMeetingID, text: "Renew the contract",
            evidence: [], createdBy: fixture.creatorID)
        let oldDecision = Decision(
            decisionID: DecisionID(rawValue: UUID()), meetingID: oldMeetingID, text: "Old decision", evidence: [],
            createdBy: fixture.creatorID)
        try await repositories.decision.insert(recentDecision, at: now)
        try await repositories.decision.insert(oldDecision, at: now)

        let brief = try await WeeklyBriefComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())

        #expect(brief.decisionsLastWeek.map(\.decisionID) == [recentDecision.decisionID])
    }

    /// `summary` is the notification body's one-liner — verify it composes
    /// cleanly when every section is empty rather than producing a
    /// dangling separator or a blank string.
    @Test func test_summary_withNoQuietThreadsOrOverdueFollowUps_stillNamesTheMeetingCount() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let fixture = try await Self.makeFixture(appDatabase)
        let repositories = Self.makeRepositories(appDatabase)

        let brief = try await WeeklyBriefComposer.compose(
            workspaceID: fixture.workspaceID, repositories: repositories, clock: SystemClock())

        #expect(brief.quietThreads.isEmpty)
        #expect(brief.overdueFollowUps.isEmpty)
        #expect(brief.summary == "0 meetings this week")
    }
}
