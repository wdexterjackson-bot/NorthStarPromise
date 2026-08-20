import CloudKit
import Foundation
import NSPCore
import NSPSync
import Testing

@testable import NSPTestSupport

@Suite("ZoneSyncEngine")
struct ZoneSyncEngineTests {
    private static func makeMeeting(meetingID: MeetingID, workspaceID: WorkspaceID) -> Meeting {
        Meeting(
            meetingID: meetingID, workspaceID: workspaceID, title: "Weekly sync", captureMode: .watch,
            originDeviceID: DeviceID(rawValue: UUID()), startedAt: Date(timeIntervalSince1970: 0),
            lifecycleState: .savedRaw, policyID: PolicyID(rawValue: UUID()), processingMode: .cloudAllowed,
            availability: .complete, createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeSegment(meetingID: MeetingID, deviceID: DeviceID, sequence: Int) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()), meetingID: meetingID, deviceID: deviceID, sequence: sequence,
            codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000, startSample: Int64(sequence) * 1000,
            sampleCount: 1000)
    }

    @Test func test_syncZone_upsertsDecodedRecordsAndComputesPartialAvailability() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())
        let meeting = Self.makeMeeting(meetingID: meetingID, workspaceID: workspaceID)
        let onlySegment = Self.makeSegment(meetingID: meetingID, deviceID: deviceID, sequence: 0)
        let zoneID = WorkspaceZone.recordZoneID(for: workspaceID)

        let gateway = FakeCloudKitGateway()
        let meetingRecord = try CloudKitRecordMapper.record(for: meeting, zoneID: zoneID)
        let segmentRecord = CloudKitRecordMapper.record(for: onlySegment, zoneID: zoneID)
        await gateway.enqueueChangePage(
            ZoneChanges(
                changedRecords: [meetingRecord, segmentRecord], deletedRecordIDs: [], cursor: gateway.makeCursor(),
                moreComing: false))

        let tokenStore = InMemoryChangeTokenStore()
        let meetingRepository = FakeMeetingRepository()
        let segmentRepository = FakeSegmentRepository()
        let engine = ZoneSyncEngine(
            gateway: gateway, tokenStore: tokenStore, meetingRepository: meetingRepository,
            segmentRepository: segmentRepository)

        let touched = try await engine.syncZone(zoneID)

        #expect(touched == [meetingID])
        let storedMeeting = try await meetingRepository.find(meetingID)
        // The decoded segment has no local audio (CKRecord never carries a
        // local file path), so the meeting must come back .partial.
        guard case .partial(let missing) = storedMeeting?.availability else {
            Issue.record("expected .partial, got \(String(describing: storedMeeting?.availability))")
            return
        }
        #expect(missing.map(\.segmentID) == [onlySegment.segmentID])
        #expect(missing[0].deviceID == deviceID)

        let storedSegment = try await segmentRepository.find(onlySegment.segmentID)
        #expect(storedSegment?.localURL == nil)
    }

    @Test func test_syncZone_advancesTheStoredCursor() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let zoneID = WorkspaceZone.recordZoneID(for: workspaceID)
        let gateway = FakeCloudKitGateway()
        let finalCursor = await gateway.makeCursor()
        await gateway.enqueueChangePage(
            ZoneChanges(changedRecords: [], deletedRecordIDs: [], cursor: finalCursor, moreComing: false))

        let tokenStore = InMemoryChangeTokenStore()
        let engine = ZoneSyncEngine(
            gateway: gateway, tokenStore: tokenStore, meetingRepository: FakeMeetingRepository(),
            segmentRepository: FakeSegmentRepository())

        _ = try await engine.syncZone(zoneID)

        let storedCursor = await tokenStore.cursor(for: zoneID)
        #expect(storedCursor == finalCursor)
    }

    @Test func test_syncZone_pagesUntilMoreComingIsFalse() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let meetingID = MeetingID(rawValue: UUID())
        let meeting = Self.makeMeeting(meetingID: meetingID, workspaceID: workspaceID)
        let zoneID = WorkspaceZone.recordZoneID(for: workspaceID)

        let gateway = FakeCloudKitGateway()
        let meetingRecord = try CloudKitRecordMapper.record(for: meeting, zoneID: zoneID)
        await gateway.enqueueChangePage(
            ZoneChanges(
                changedRecords: [meetingRecord], deletedRecordIDs: [], cursor: gateway.makeCursor(), moreComing: true))
        await gateway.enqueueChangePage(
            ZoneChanges(changedRecords: [], deletedRecordIDs: [], cursor: gateway.makeCursor(), moreComing: false))

        let engine = ZoneSyncEngine(
            gateway: gateway, tokenStore: InMemoryChangeTokenStore(), meetingRepository: FakeMeetingRepository(),
            segmentRepository: FakeSegmentRepository())

        _ = try await engine.syncZone(zoneID)

        let calls = await gateway.calls
        let fetchCount = calls.filter { if case .fetchChanges = $0 { return true } else { return false } }.count
        #expect(fetchCount == 2)
    }
}
