import CloudKit
import Foundation
import NSPCore
import Testing

@testable import NSPSync

@Suite("CloudKitRecordMapper")
struct CloudKitRecordMapperTests {
    private static func makeMeeting() -> Meeting {
        Meeting(
            meetingID: MeetingID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()),
            title: "Weekly sync", isTitleSensitive: true, calendarEventID: "cal-123", captureMode: .watch,
            originDeviceID: DeviceID(rawValue: UUID()), startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2000),
            canonicalDuration: SampleDuration(sampleCount: 96000, sampleRate: 16000),
            lifecycleState: .failed(reason: "storage exhausted"), policyID: PolicyID(rawValue: UUID()),
            processingMode: .cloudAllowed, consentRecordID: ConsentRecordID(rawValue: UUID()),
            availability: .partial(
                missing: [
                    SegmentRef(
                        segmentID: SegmentID(rawValue: UUID()), deviceID: DeviceID(rawValue: UUID()), sequence: 3)
                ]),
            excludedFromMemory: true, createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: Date(timeIntervalSince1970: 1500), deletedAt: nil)
    }

    @Test func test_workspaceZone_matchesTheDocumentedNamingConvention() {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let zoneID = WorkspaceZone.recordZoneID(for: workspaceID)
        #expect(zoneID.zoneName == "ws-\(workspaceID.rawValue.uuidString)")
    }

    @Test func test_recordTypes_matchDocs02Section6Verbatim() {
        #expect(CloudKitRecordType.meeting == "CD_Meeting")
        #expect(CloudKitRecordType.segment == "CD_Segment")
        #expect(CloudKitRecordType.transcriptTurn == "CD_TranscriptTurn")
    }

    @Test func test_meeting_roundTripsThroughACKRecord() throws {
        let meeting = Self.makeMeeting()
        let zoneID = WorkspaceZone.recordZoneID(for: meeting.workspaceID)

        let record = try CloudKitRecordMapper.record(for: meeting, zoneID: zoneID)
        #expect(record.recordType == CloudKitRecordType.meeting)
        #expect(record.recordID.recordName == meeting.meetingID.rawValue.uuidString)

        let recovered = try CloudKitRecordMapper.meeting(from: record)
        #expect(recovered == meeting)
    }

    @Test func test_meeting_titleIsStoredThroughEncryptedValues() throws {
        let meeting = Self.makeMeeting()
        let record = try CloudKitRecordMapper.record(
            for: meeting, zoneID: WorkspaceZone.recordZoneID(for: meeting.workspaceID))

        #expect(record["title"] == nil)
        #expect(record.encryptedValues["title"] as? String == meeting.title)
    }

    @Test func test_segment_recordCarriesTheCorrectType() {
        let meetingID = MeetingID(rawValue: UUID())
        let segment = Segment(
            segmentID: SegmentID(rawValue: UUID()), owner: .meeting(meetingID), deviceID: DeviceID(rawValue: UUID()),
            sequence: 0, codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000, startSample: 0,
            sampleCount: 1000, sha256: Data(repeating: 1, count: 32))
        let zoneID = WorkspaceZone.recordZoneID(for: WorkspaceID(rawValue: UUID()))

        let record = CloudKitRecordMapper.record(for: segment, zoneID: zoneID)

        #expect(record.recordType == CloudKitRecordType.segment)
        #expect(record["meetingID"] as? String == meetingID.rawValue.uuidString)
        #expect(record["sha256"] as? Data == segment.sha256)
    }

    @Test func test_transcriptTurn_recordCarriesTheCorrectType() throws {
        let meetingID = MeetingID(rawValue: UUID())
        let turn = TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), owner: .meeting(meetingID), revision: 1, isProvisional: false,
            tokens: [Token(text: "hi", startSample: 0, endSample: 100, confidence: 0.9)], segmentRefs: [])
        let zoneID = WorkspaceZone.recordZoneID(for: WorkspaceID(rawValue: UUID()))

        let record = try CloudKitRecordMapper.record(for: turn, zoneID: zoneID)

        #expect(record.recordType == CloudKitRecordType.transcriptTurn)
        #expect(record["meetingID"] as? String == meetingID.rawValue.uuidString)
    }
}
