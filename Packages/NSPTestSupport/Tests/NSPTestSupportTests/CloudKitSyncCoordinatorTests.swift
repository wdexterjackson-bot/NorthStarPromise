import Foundation
import NSPCore
import NSPPolicy
import NSPSync
import Testing

@testable import NSPTestSupport

/// NSP-034's acceptance: "`.localOnly` meetings produce zero CloudKit
/// writes (test)." Proven directly against `CloudKitSyncCoordinator` and a
/// `FakeCloudKitGateway` that records every call it receives.
@Suite("CloudKitSyncCoordinator")
struct CloudKitSyncCoordinatorTests {
    private static func makeMeeting(mode: ProcessingMode, policyID: PolicyID) -> Meeting {
        Meeting(
            meetingID: MeetingID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()), title: "Standup",
            captureMode: .watch, originDeviceID: DeviceID(rawValue: UUID()), startedAt: Date(timeIntervalSince1970: 0),
            lifecycleState: .savedRaw, policyID: policyID, processingMode: mode, availability: .complete,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func test_localOnlyMeeting_neverCallsTheGatewayAtAll() async throws {
        let policyID = PolicyID(rawValue: UUID())
        let policy = Policy(
            policyID: policyID, workspaceID: WorkspaceID(rawValue: UUID()), defaultProcessingMode: .localOnly)
        let meeting = Self.makeMeeting(mode: .localOnly, policyID: policyID)

        let policyLookup = FakePolicySnapshotLookup()
        await policyLookup.setPolicy(policy, for: meeting.meetingID)
        let networkGate = DefaultNetworkGate(
            auditRecorder: FakeAuditEventRecorder(), consentLookup: FakeConsentRecordLookup(),
            policyLookup: policyLookup)
        let gateway = FakeCloudKitGateway()
        let coordinator = CloudKitSyncCoordinator(networkGate: networkGate, gateway: gateway)

        await #expect(throws: SyncError.self) {
            try await coordinator.syncMeeting(meeting)
        }
        await #expect(throws: SyncError.self) {
            try await coordinator.bootstrapZone(for: meeting)
        }

        let calls = await gateway.calls
        #expect(calls.isEmpty)
    }

    @Test func test_cloudAllowedMeetingWithConsent_writesTheMeetingRecord() async throws {
        let policyID = PolicyID(rawValue: UUID())
        let policy = Policy(
            policyID: policyID, workspaceID: WorkspaceID(rawValue: UUID()), defaultProcessingMode: .cloudAllowed)
        let meeting = Self.makeMeeting(mode: .cloudAllowed, policyID: policyID)

        let policyLookup = FakePolicySnapshotLookup()
        await policyLookup.setPolicy(policy, for: meeting.meetingID)
        let consentLookup = FakeConsentRecordLookup()
        await consentLookup.grantConsent(for: meeting.meetingID)
        let networkGate = DefaultNetworkGate(
            auditRecorder: FakeAuditEventRecorder(), consentLookup: consentLookup, policyLookup: policyLookup)
        let gateway = FakeCloudKitGateway()
        let coordinator = CloudKitSyncCoordinator(networkGate: networkGate, gateway: gateway)

        let record = try await coordinator.syncMeeting(meeting)

        #expect(record.recordType == CloudKitRecordType.meeting)
        let calls = await gateway.calls
        #expect(calls.contains(.fetchOrCreateZone(WorkspaceZone.recordZoneID(for: meeting.workspaceID))))
        #expect(calls.contains(.save([record.recordID])))
    }

    @Test func test_onDevicePreferredMeeting_stillWritesTheMeetingRecord() async throws {
        // docs/06 §1.1: CloudKit private-DB writes are permitted under
        // .onDevicePreferred — only cloud AI processing is forbidden.
        let policyID = PolicyID(rawValue: UUID())
        let policy = Policy(
            policyID: policyID, workspaceID: WorkspaceID(rawValue: UUID()), defaultProcessingMode: .onDevicePreferred)
        let meeting = Self.makeMeeting(mode: .onDevicePreferred, policyID: policyID)

        let policyLookup = FakePolicySnapshotLookup()
        await policyLookup.setPolicy(policy, for: meeting.meetingID)
        let consentLookup = FakeConsentRecordLookup()
        await consentLookup.grantConsent(for: meeting.meetingID)
        let networkGate = DefaultNetworkGate(
            auditRecorder: FakeAuditEventRecorder(), consentLookup: consentLookup, policyLookup: policyLookup)
        let gateway = FakeCloudKitGateway()
        let coordinator = CloudKitSyncCoordinator(networkGate: networkGate, gateway: gateway)

        _ = try await coordinator.syncMeeting(meeting)

        let calls = await gateway.calls
        #expect(!calls.isEmpty)
    }
}
