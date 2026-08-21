import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBSegmentRepository")
struct GRDBSegmentRepositoryTests {
    private static func makeMeetingGraph(_ appDatabase: AppDatabase, meetingID: MeetingID) async throws {
        let meetingIDString = meetingID.rawValue.uuidString
        try await appDatabase.dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (workspace_id, name, created_at, updated_at, row_revision) "
                    + "VALUES ('w1', 'Workspace', '2026-01-01', '2026-01-01', 1)")
            try db.execute(
                sql: """
                    INSERT INTO policy (
                        policy_id, workspace_id, default_processing_mode, announcement_required,
                        created_at, updated_at, row_revision
                    ) VALUES ('p1', 'w1', 'localOnly', 0, '2026-01-01', '2026-01-01', 1)
                    """)
            try db.execute(
                sql: """
                    INSERT INTO meeting (
                        meeting_id, workspace_id, title, is_title_sensitive, capture_mode, origin_device_id,
                        started_at, lifecycle_state, policy_id, processing_mode, availability,
                        excluded_from_memory, created_at, updated_at, row_revision
                    ) VALUES (
                        ?, 'w1', 'Test meeting', 0, 'watch', 'AAAAAAAA-0000-7000-8000-000000000001',
                        '2026-01-01', 'ready', 'p1', 'localOnly', 'complete',
                        0, '2026-01-01', '2026-01-01', 1
                    )
                    """, arguments: [meetingIDString])
        }
    }

    private static func makeSegment(meetingID: MeetingID, sequence: Int) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()),
            owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            sequence: sequence,
            codec: .aacLC,
            sampleRate: 16_000,
            channels: 1,
            bitRate: 32_000,
            startSample: Int64(sequence) * 720_000,
            sampleCount: 720_000,
            sha256: Data(repeating: UInt8(sequence), count: 32),
            transferState: .local,
            isRepairedTail: false
        )
    }

    @Test func test_insertThenFind_roundTripsAllFields() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let segment = Self.makeSegment(meetingID: meetingID, sequence: 0)

        try await repository.insert(segment, at: Date(timeIntervalSince1970: 1_700_000_000))
        let found = try await repository.find(segment.segmentID)

        #expect(found == segment)
    }

    @Test func test_update_incrementsRowRevisionAndPersistsChanges() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        var segment = Self.makeSegment(meetingID: meetingID, sequence: 0)
        try await repository.insert(segment, at: Date(timeIntervalSince1970: 1_700_000_000))

        segment.transferState = .verified
        segment.localURL = nil
        try await repository.update(segment, at: Date(timeIntervalSince1970: 1_700_000_100))

        let found = try await repository.find(segment.segmentID)
        #expect(found?.transferState == .verified)

        let segmentIDString = segment.segmentID.rawValue.uuidString
        let rowRevision = try await appDatabase.dbWriter.read { db in
            try Int.fetchOne(
                db, sql: "SELECT row_revision FROM segment WHERE segment_id = ?",
                arguments: [segmentIDString])
        }
        #expect(rowRevision == 2)
    }

    @Test func test_update_missingRow_throwsNotFound() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let segment = Self.makeSegment(meetingID: meetingID, sequence: 0)

        await #expect(throws: PersistenceError.self) {
            try await repository.update(segment, at: Date())
        }
    }

    @Test func test_fetchAll_ordersBySequence() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        for sequence in [2, 0, 1] {
            try await repository.insert(Self.makeSegment(meetingID: meetingID, sequence: sequence), at: Date())
        }

        let all = try await repository.fetchAll(owner: .meeting(meetingID))
        #expect(all.map(\.sequence) == [0, 1, 2])
    }

    @Test func test_findUploaded_matchesOnlyASegmentWithBothTheHashAndACloudAssetRef() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let sharedHash = Data(repeating: 0xAB, count: 32)

        var notYetUploaded = Self.makeSegment(meetingID: meetingID, sequence: 0)
        notYetUploaded.sha256 = sharedHash
        try await repository.insert(notYetUploaded, at: Date())

        var uploaded = Self.makeSegment(meetingID: meetingID, sequence: 1)
        uploaded.sha256 = sharedHash
        uploaded.cloudAssetRef = "record-name-abc"
        try await repository.insert(uploaded, at: Date())

        let found = try await repository.findUploaded(sha256: sharedHash)
        #expect(found?.segmentID == uploaded.segmentID)
    }

    @Test func test_findUploaded_returnsNilWhenNoSegmentHasThatHash() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = MeetingID(rawValue: UUID(uuidString: "aaaaaaaa-0000-7000-8000-000000000000")!)
        try await Self.makeMeetingGraph(appDatabase, meetingID: meetingID)

        let repository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        try await repository.insert(Self.makeSegment(meetingID: meetingID, sequence: 0), at: Date())

        let found = try await repository.findUploaded(sha256: Data(repeating: 0xFF, count: 32))
        #expect(found == nil)
    }
}
