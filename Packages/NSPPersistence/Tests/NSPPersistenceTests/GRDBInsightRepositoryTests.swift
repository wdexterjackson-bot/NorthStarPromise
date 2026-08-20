import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBInsightRepository")
struct GRDBInsightRepositoryTests {
    private static func makeMeeting(_ appDatabase: AppDatabase) async throws -> MeetingID {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let policyID = PolicyID(rawValue: UUID())
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
        return meetingID
    }

    private static func makeInsight(meetingID: MeetingID, evidence: [EvidenceSpan] = []) -> Insight {
        Insight(
            insightID: InsightID(rawValue: UUID()), meetingID: meetingID, layer: .executiveSummary,
            text: "The team agreed to ship by Friday.", claimKind: evidence.isEmpty ? .aiSuggests : .agreed,
            evidence: evidence, confidence: 0.87,
            provenance: Provenance(
                modelID: "on-device-summarizer", modelVersion: "1", promptVersion: "1",
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000), processingPlane: .onDevice))
    }

    @Test func test_insertThenFind_roundTripsAllFieldsWithNoEvidence() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)

        let insight = Self.makeInsight(meetingID: meetingID)
        try await repository.insert(insight, at: Date())
        let found = try await repository.find(insight.insightID)

        #expect(found == insight)
    }

    @Test func test_insertThenFind_roundTripsEvidenceSpans() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)

        let evidence = [
            EvidenceSpan(
                meetingID: meetingID, turnIDs: [], sampleRange: SampleRange(startSample: 500, endSample: 900),
                quotedText: "we'll ship by Friday", transcriptRevision: 1)
        ]
        let insight = Self.makeInsight(meetingID: meetingID, evidence: evidence)
        try await repository.insert(insight, at: Date())
        let found = try await repository.find(insight.insightID)

        #expect(found?.evidence == evidence)
    }

    @Test func test_fetchAll_returnsEveryInsightForTheMeeting() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)

        try await repository.insert(Self.makeInsight(meetingID: meetingID), at: Date())
        try await repository.insert(Self.makeInsight(meetingID: meetingID), at: Date())

        #expect(try await repository.fetchAll(meetingID: meetingID).count == 2)
    }

    @Test func test_update_missingRow_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeeting(appDatabase)
        let repository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)
        await #expect(throws: PersistenceError.self) {
            try await repository.update(Self.makeInsight(meetingID: meetingID), at: Date())
        }
    }

    @Test func test_find_missingInsight_returnsNil() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let repository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)
        #expect(try await repository.find(InsightID(rawValue: UUID())) == nil)
    }
}
