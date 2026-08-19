import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy
import Testing

@testable import NSPTestSupport

@Suite("Fake NetworkGate collaborators")
struct FakeNetworkGateCollaboratorsTests {
    @Test func test_auditEventRecorder_recordsInOrder() async throws {
        let recorder = FakeAuditEventRecorder()
        let first = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()), actorID: nil, action: "a", object: "o",
            payloadHash: "h", result: .success, timestamp: Date())
        let second = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()), actorID: nil, action: "b", object: "o",
            payloadHash: "h", result: .denied, timestamp: Date())

        try await recorder.record(first)
        try await recorder.record(second)

        let events = await recorder.recordedEvents
        #expect(events == [first, second])
    }

    @Test func test_auditEventRecorder_failingModeThrows() async throws {
        let recorder = FakeAuditEventRecorder(failing: true)
        let event = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()), actorID: nil, action: "a", object: "o",
            payloadHash: "h", result: .success, timestamp: Date())

        await #expect(throws: PersistenceError.self) {
            try await recorder.record(event)
        }
    }

    @Test func test_consentRecordLookup_reflectsGrantedConsent() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let lookup = FakeConsentRecordLookup()

        #expect(await lookup.hasConsentRecord(for: meetingID) == false)
        await lookup.grantConsent(for: meetingID)
        #expect(await lookup.hasConsentRecord(for: meetingID) == true)
    }

    @Test func test_policySnapshotLookup_returnsWhatWasSet() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()),
            defaultProcessingMode: .cloudAllowed)
        let lookup = FakePolicySnapshotLookup()

        #expect(await lookup.policy(for: meetingID) == nil)
        await lookup.setPolicy(policy, for: meetingID)
        #expect(await lookup.policy(for: meetingID) == policy)
    }
}
