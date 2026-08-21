import Foundation
import NSPCore
import NSPPolicy
import NSPSync
import Testing

@testable import NSPTestSupport

/// NSP-035's acceptance: "Duplicate upload of the same hash collapses;
/// upload resumes after interruption."
@Suite("CKAssetUploader")
struct CKAssetUploaderTests {
    private static func makeMeeting(policyID: PolicyID, mode: ProcessingMode = .cloudAllowed) -> Meeting {
        Meeting(
            meetingID: MeetingID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()), title: "Standup",
            captureMode: .watch, originDeviceID: DeviceID(rawValue: UUID()), startedAt: Date(timeIntervalSince1970: 0),
            lifecycleState: .savedRaw, policyID: policyID, processingMode: mode, availability: .complete,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeSegment(meetingID: MeetingID, sha256: Data) -> Segment {
        Segment(
            segmentID: SegmentID(rawValue: UUID()), owner: .meeting(meetingID), deviceID: DeviceID(rawValue: UUID()),
            sequence: 0, codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000, startSample: 0,
            sampleCount: 1000, sha256: sha256)
    }

    private struct Deps {
        let networkGate: DefaultNetworkGate
        let gateway: FakeCloudKitGateway
        let segmentRepository: FakeSegmentRepository
    }

    private static func makeDeps(meeting: Meeting) async -> Deps {
        let policy = Policy(
            policyID: meeting.policyID, workspaceID: meeting.workspaceID, defaultProcessingMode: meeting.processingMode)
        let policyLookup = FakePolicySnapshotLookup()
        await policyLookup.setPolicy(policy, for: meeting.meetingID)
        let consentLookup = FakeConsentRecordLookup()
        await consentLookup.grantConsent(for: meeting.meetingID)
        let networkGate = DefaultNetworkGate(
            auditRecorder: FakeAuditEventRecorder(), consentLookup: consentLookup, policyLookup: policyLookup)
        return Deps(
            networkGate: networkGate, gateway: FakeCloudKitGateway(), segmentRepository: FakeSegmentRepository())
    }

    @Test func test_firstUpload_savesTheRecordAndReturnsItsRecordName() async throws {
        let meeting = Self.makeMeeting(policyID: PolicyID(rawValue: UUID()))
        let segment = Self.makeSegment(meetingID: meeting.meetingID, sha256: Data(repeating: 1, count: 32))
        let deps = await Self.makeDeps(meeting: meeting)
        let uploader = CKAssetUploader(
            networkGate: deps.networkGate, gateway: deps.gateway, segmentRepository: deps.segmentRepository)

        let ref = try await uploader.upload(segment, meeting: meeting)

        #expect(ref == segment.segmentID.rawValue.uuidString)
        let calls = await deps.gateway.calls
        #expect(calls.contains { if case .save = $0 { return true } else { return false } })
    }

    @Test func test_duplicateHash_collapsesToTheExistingAssetWithoutTouchingTheGateway() async throws {
        let meeting = Self.makeMeeting(policyID: PolicyID(rawValue: UUID()))
        let sharedHash = Data(repeating: 7, count: 32)
        let deps = await Self.makeDeps(meeting: meeting)

        var alreadyUploaded = Self.makeSegment(meetingID: meeting.meetingID, sha256: sharedHash)
        alreadyUploaded.cloudAssetRef = "existing-record-name"
        try await deps.segmentRepository.insert(alreadyUploaded, at: Date())

        let newSegmentSameAudio = Self.makeSegment(meetingID: meeting.meetingID, sha256: sharedHash)
        let uploader = CKAssetUploader(
            networkGate: deps.networkGate, gateway: deps.gateway, segmentRepository: deps.segmentRepository)

        let ref = try await uploader.upload(newSegmentSameAudio, meeting: meeting)

        #expect(ref == "existing-record-name")
        let calls = await deps.gateway.calls
        #expect(calls.isEmpty)
    }

    @Test func test_retryAfterInterruption_savesOverTheSameRecordIDBothTimes() async throws {
        let meeting = Self.makeMeeting(policyID: PolicyID(rawValue: UUID()))
        let segment = Self.makeSegment(meetingID: meeting.meetingID, sha256: Data(repeating: 2, count: 32))
        let deps = await Self.makeDeps(meeting: meeting)
        let uploader = CKAssetUploader(
            networkGate: deps.networkGate, gateway: deps.gateway, segmentRepository: deps.segmentRepository)

        let firstAttemptRef = try await uploader.upload(segment, meeting: meeting)
        // Simulated interruption: the local DB was never updated with the
        // ref, so a retry doesn't see a dedupe hit and re-attempts the save.
        let secondAttemptRef = try await uploader.upload(segment, meeting: meeting)

        #expect(firstAttemptRef == secondAttemptRef)
        let saveCallCount = await deps.gateway.calls.filter { if case .save = $0 { return true } else { return false } }
            .count
        #expect(saveCallCount == 2)
    }

    @Test func test_localOnlyMeeting_neverCallsTheGateway() async throws {
        let policyID = PolicyID(rawValue: UUID())
        let meeting = Self.makeMeeting(policyID: policyID, mode: .localOnly)
        let segment = Self.makeSegment(meetingID: meeting.meetingID, sha256: Data(repeating: 3, count: 32))
        let deps = await Self.makeDeps(meeting: meeting)
        let uploader = CKAssetUploader(
            networkGate: deps.networkGate, gateway: deps.gateway, segmentRepository: deps.segmentRepository)

        await #expect(throws: SyncError.self) {
            try await uploader.upload(segment, meeting: meeting)
        }
        let calls = await deps.gateway.calls
        #expect(calls.isEmpty)
    }
}
