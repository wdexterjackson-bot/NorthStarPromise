import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

@Suite("GRDBTimelineEventRepository")
struct GRDBTimelineEventRepositoryTests {
    private static func makeMeetingGraph(_ appDatabase: AppDatabase) async throws -> MeetingID {
        let meetingID = MeetingID(rawValue: UUID())
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
                    """, arguments: [meetingID.rawValue.uuidString])
        }
        return meetingID
    }

    private static func makeEvent(
        meetingID: MeetingID, type: TimelineEventType, sampleOffset: Int64, payload: JSONValue? = nil
    ) -> TimelineEvent {
        TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()),
            owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            type: type,
            sampleOffset: sampleOffset,
            wallClock: Date(timeIntervalSince1970: 1_700_000_000),
            payload: payload
        )
    }

    @Test func test_append_roundTripsEveryEventTypeCase() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)

        let events: [TimelineEvent] = [
            Self.makeEvent(meetingID: meetingID, type: .start, sampleOffset: 0),
            Self.makeEvent(meetingID: meetingID, type: .pause, sampleOffset: 1_000),
            Self.makeEvent(meetingID: meetingID, type: .resume, sampleOffset: 2_000),
            Self.makeEvent(
                meetingID: meetingID, type: .interruptionBegan(cause: .phoneCall), sampleOffset: 3_000),
            Self.makeEvent(meetingID: meetingID, type: .interruptionEnded, sampleOffset: 4_000),
            Self.makeEvent(
                meetingID: meetingID,
                type: .routeChange(from: .builtInMic, to: .airpods), sampleOffset: 5_000),
            Self.makeEvent(meetingID: meetingID, type: .marker(kind: .important), sampleOffset: 6_000),
            Self.makeEvent(
                meetingID: meetingID, type: .levelWarning(kind: .clipping), sampleOffset: 7_000),
            Self.makeEvent(meetingID: meetingID, type: .thermal(state: .serious), sampleOffset: 8_000),
            Self.makeEvent(meetingID: meetingID, type: .batteryWarning, sampleOffset: 9_000),
            Self.makeEvent(meetingID: meetingID, type: .storageWarning, sampleOffset: 10_000),
            Self.makeEvent(
                meetingID: meetingID, type: .sealedStop(reason: .batteryCritical), sampleOffset: 11_000),
            Self.makeEvent(
                meetingID: meetingID, type: .stop, sampleOffset: 12_000,
                payload: .object(["note": .string("sealed cleanly")])),
        ]
        for event in events {
            try await repository.append(event, at: Date())
        }

        let fetched = try await repository.fetchAll(owner: .meeting(meetingID))
        #expect(fetched == events)
    }

    @Test func test_fetchAll_ordersBySampleOffsetNotWallClock() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let meetingID = try await Self.makeMeetingGraph(appDatabase)
        let repository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)

        // Insert with sample offsets out of order and wall clocks that would
        // sort the opposite way, to prove sample_offset — not wall_clock —
        // drives ordering (docs/03 §4).
        let later = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            type: .marker(kind: .important), sampleOffset: 5_000,
            wallClock: Date(timeIntervalSince1970: 1_700_000_000))
        let earlier = TimelineEvent(
            eventID: TimelineEventID(rawValue: UUID()), owner: .meeting(meetingID),
            deviceID: DeviceID(rawValue: UUID()),
            type: .marker(kind: .actionItem), sampleOffset: 1_000,
            wallClock: Date(timeIntervalSince1970: 1_700_000_500))

        try await repository.append(later, at: Date())
        try await repository.append(earlier, at: Date())

        let fetched = try await repository.fetchAll(owner: .meeting(meetingID))
        #expect(fetched.map(\.eventID) == [earlier.eventID, later.eventID])
    }
}
