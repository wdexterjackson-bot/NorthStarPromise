import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBActionRepository")
struct GRDBActionRepositoryTests {
    /// A named type in place of a 3-member tuple (SwiftLint's `large_tuple`
    /// rule caps tuples at 2) — the same pattern `NoteBlockRow.EncodedContent`
    /// and `MeetingStateBadge.Appearance` use elsewhere in this codebase.
    private struct MeetingGraph {
        let workspaceID: WorkspaceID
        let meetingID: MeetingID
        let personID: PersonID
    }

    private static func makeMeetingGraph(_ appDatabase: AppDatabase) async throws -> MeetingGraph {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
        let personID = PersonID(rawValue: UUID())
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
                sql: """
                    INSERT INTO person (person_id, workspace_id, name, created_at, updated_at, row_revision)
                    VALUES (?, ?, 'Author', '2026-01-01', '2026-01-01', 1)
                    """, arguments: [personID.rawValue.uuidString, workspaceID.rawValue.uuidString])
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Test meeting', 0, 'watch', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'ready', ?, 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """,
                arguments: [
                    meetingID.rawValue.uuidString, workspaceID.rawValue.uuidString, policyID.rawValue.uuidString,
                ])
        }
        return MeetingGraph(workspaceID: workspaceID, meetingID: meetingID, personID: personID)
    }

    private static func makeAction(
        meetingID: MeetingID, createdBy: PersonID, owner: ResolvedValue<PersonID> = .unresolved,
        date: ResolvedValue<Date> = .unresolved, status: ActionStatus = .proposed
    ) -> Action {
        Action(
            actionID: ActionID(rawValue: UUID()), meetingID: meetingID, text: "Send the recap", owner: owner,
            date: date, status: status, evidence: [], createdBy: createdBy)
    }

    @Test func test_insertThenFind_roundTripsEvidenceSpans() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)

        let evidence = [
            EvidenceSpan(
                meetingID: graph.meetingID, turnIDs: [], sampleRange: SampleRange(startSample: 1000, endSample: 2000),
                quotedText: "I'll send the recap by Friday", transcriptRevision: 1)
        ]
        var action = Self.makeAction(meetingID: graph.meetingID, createdBy: graph.personID)
        action = Action(
            actionID: action.actionID, meetingID: action.meetingID, text: action.text, owner: action.owner,
            date: action.date, status: action.status, evidence: evidence, createdBy: action.createdBy)

        try await repository.insert(action, at: Date())
        let found = try await repository.find(action.actionID)

        #expect(found?.evidence == evidence)
    }

    @Test func test_update_replacesEvidenceRatherThanAccumulating() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)

        let firstSpan = EvidenceSpan(
            meetingID: graph.meetingID, turnIDs: [], sampleRange: SampleRange(startSample: 0, endSample: 100),
            quotedText: "first", transcriptRevision: 1)
        var action = Self.makeAction(meetingID: graph.meetingID, createdBy: graph.personID)
        action = Action(
            actionID: action.actionID, meetingID: action.meetingID, text: action.text, owner: action.owner,
            date: action.date, status: action.status, evidence: [firstSpan], createdBy: action.createdBy)
        try await repository.insert(action, at: Date())

        let secondSpan = EvidenceSpan(
            meetingID: graph.meetingID, turnIDs: [], sampleRange: SampleRange(startSample: 200, endSample: 300),
            quotedText: "second", transcriptRevision: 1)
        action = Action(
            actionID: action.actionID, meetingID: action.meetingID, text: action.text, owner: action.owner,
            date: action.date, status: action.status, evidence: [secondSpan], createdBy: action.createdBy)
        try await repository.update(action, at: Date())

        let found = try await repository.find(action.actionID)
        #expect(found?.evidence == [secondSpan])
    }

    @Test func test_insertThenFind_roundTripsUnresolvedFields() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let action = Self.makeAction(meetingID: meetingID, createdBy: personID)

        try await repository.insert(action, at: Date(timeIntervalSince1970: 1_700_000_000))
        let found = try await repository.find(action.actionID)

        #expect(found == action)
    }

    @Test func test_insertThenFind_roundTripsExplicitOwnerAndDate() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let dueDate = Date(timeIntervalSince1970: 1_700_100_000)
        let action = Self.makeAction(
            meetingID: meetingID, createdBy: personID, owner: .explicit(personID), date: .inferred(dueDate))

        try await repository.insert(action, at: Date())
        let found = try await repository.find(action.actionID)

        #expect(found?.owner == .explicit(personID))
        #expect(found?.date == .inferred(dueDate))
    }

    @Test func test_insertThenFind_roundTripsTheAuditTrailInOrder() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        var action = Self.makeAction(meetingID: meetingID, createdBy: personID)
        action.auditTrail = [
            AuditEntry(actorID: personID, action: "created", at: Date(timeIntervalSince1970: 1)),
            AuditEntry(actorID: personID, action: "confirmed", at: Date(timeIntervalSince1970: 2)),
        ]

        try await repository.insert(action, at: Date())
        let found = try await repository.find(action.actionID)

        #expect(found?.auditTrail.map(\.action) == ["created", "confirmed"])
    }

    @Test func test_update_missingRow_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let action = Self.makeAction(meetingID: meetingID, createdBy: personID)

        await #expect(throws: PersistenceError.self) { try await repository.update(action, at: Date()) }
    }

    @Test func test_fetchAllByMeeting_returnsOnlyThatMeetingsActions() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let first = Self.makeAction(meetingID: meetingID, createdBy: personID)
        let second = Self.makeAction(meetingID: meetingID, createdBy: personID)
        try await repository.insert(first, at: Date())
        try await repository.insert(second, at: Date())

        let all = try await repository.fetchAll(meetingID: meetingID)

        #expect(Set(all.map(\.actionID)) == Set([first.actionID, second.actionID]))
    }

    @Test func test_fetchAllByWorkspace_joinsThroughMeetingAcrossMultipleMeetings() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let workspaceID = graph.workspaceID
        let firstMeetingID = graph.meetingID
        let personID = graph.personID
        let secondMeetingID = MeetingID(rawValue: UUID())
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, ?, 'Second meeting', 0, 'watch', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-02', 'ready', (SELECT policy_id FROM policy LIMIT 1), 'localOnly', 'complete',
                        0, '2026-01-02', '2026-01-02', 1
                    )
                    """, arguments: [secondMeetingID.rawValue.uuidString, workspaceID.rawValue.uuidString])
        }
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let first = Self.makeAction(meetingID: firstMeetingID, createdBy: personID)
        let second = Self.makeAction(meetingID: secondMeetingID, createdBy: personID)
        try await repository.insert(first, at: Date())
        try await repository.insert(second, at: Date())

        let all = try await repository.fetchAll(workspaceID: workspaceID)

        #expect(Set(all.map(\.actionID)) == Set([first.actionID, second.actionID]))
    }

    @Test func test_delete_removesTheActionAndItsAuditTrail() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let graph = try await Self.makeMeetingGraph(appDatabase)
        let meetingID = graph.meetingID
        let personID = graph.personID
        let repository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let action = Self.makeAction(meetingID: meetingID, createdBy: personID)
        try await repository.insert(action, at: Date())

        try await repository.delete(action.actionID)

        let found = try await repository.find(action.actionID)
        #expect(found == nil)
    }
}
