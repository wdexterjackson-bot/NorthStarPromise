import Foundation
import NSPCore
import Testing

@testable import NSPPolicy

private struct RecordingFailed: Error {}

@Suite("DefaultNetworkGate")
struct NetworkGateTests {
    private actor SpyAuditEventRecorder: AuditEventRecorder {
        private(set) var recordedEvents: [AuditEvent] = []
        private let failing: Bool

        init(failing: Bool = false) { self.failing = failing }

        func record(_ event: AuditEvent) async throws {
            if failing {
                throw RecordingFailed()
            }
            recordedEvents.append(event)
        }
    }

    private actor StubConsentRecordLookup: ConsentRecordLookup {
        private var meetingsWithConsent: Set<MeetingID>
        init(meetingsWithConsent: Set<MeetingID> = []) { self.meetingsWithConsent = meetingsWithConsent }
        func hasConsentRecord(for meetingID: MeetingID) async -> Bool { meetingsWithConsent.contains(meetingID) }
    }

    private actor StubPolicySnapshotLookup: PolicySnapshotLookup {
        private var policies: [MeetingID: Policy] = [:]
        func set(_ policy: Policy, for meetingID: MeetingID) { policies[meetingID] = policy }
        func policy(for meetingID: MeetingID) async -> Policy? { policies[meetingID] }
    }

    private static func makePolicy(mode: ProcessingMode) -> Policy {
        Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()),
            defaultProcessingMode: mode)
    }

    private static func makeRequest(
        meetingID: MeetingID, purpose: EgressPurpose = .transcription, classes: Set<ContentClass> = [.transcript]
    ) -> EgressRequest {
        EgressRequest(
            meetingID: meetingID, purpose: purpose, classes: classes, byteCount: 128,
            payloadSHA256: "deadbeef", destination: .backendProcessingPlane)
    }

    @Test func test_localOnlyMeeting_alwaysDeniesAndNeverConstructsAGrant() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        await policyLookup.set(Self.makePolicy(mode: .localOnly), for: meetingID)
        let auditRecorder = SpyAuditEventRecorder()
        let gate = DefaultNetworkGate(
            auditRecorder: auditRecorder, consentLookup: StubConsentRecordLookup(meetingsWithConsent: [meetingID]),
            policyLookup: policyLookup)

        let decision = await gate.authorize(Self.makeRequest(meetingID: meetingID, purpose: .cloudKitSync))

        guard case .denied(.localOnlyMeeting) = decision else {
            Issue.record("expected .denied(.localOnlyMeeting), got \(decision)")
            return
        }
        let events = await auditRecorder.recordedEvents
        #expect(events.count == 1)
        #expect(events[0].result == .denied)
    }

    @Test func test_onDevicePreferred_allowsOnlyCloudKitSync() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        await policyLookup.set(Self.makePolicy(mode: .onDevicePreferred), for: meetingID)
        let gate = DefaultNetworkGate(
            auditRecorder: SpyAuditEventRecorder(),
            consentLookup: StubConsentRecordLookup(meetingsWithConsent: [meetingID]), policyLookup: policyLookup)

        let syncDecision = await gate.authorize(Self.makeRequest(meetingID: meetingID, purpose: .cloudKitSync))
        guard case .allowed = syncDecision else {
            Issue.record("expected cloudKitSync to be allowed under onDevicePreferred, got \(syncDecision)")
            return
        }

        let transcriptionDecision = await gate.authorize(
            Self.makeRequest(meetingID: meetingID, purpose: .transcription))
        guard case .denied(.workspacePolicyBlocked) = transcriptionDecision else {
            Issue.record("expected transcription to deny under onDevicePreferred, got \(transcriptionDecision)")
            return
        }
    }

    @Test func test_cloudAllowed_withoutConsentRecord_denies() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        await policyLookup.set(Self.makePolicy(mode: .cloudAllowed), for: meetingID)
        let gate = DefaultNetworkGate(
            auditRecorder: SpyAuditEventRecorder(), consentLookup: StubConsentRecordLookup(), policyLookup: policyLookup
        )

        let decision = await gate.authorize(Self.makeRequest(meetingID: meetingID))

        guard case .denied(.noConsentRecord) = decision else {
            Issue.record("expected .denied(.noConsentRecord), got \(decision)")
            return
        }
    }

    @Test func test_cloudAllowed_withConsent_mintsAGrantWithMappedCapabilitiesAndAnAuditEvent() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        let policy = Self.makePolicy(mode: .cloudAllowed)
        await policyLookup.set(policy, for: meetingID)
        let auditRecorder = SpyAuditEventRecorder()
        let gate = DefaultNetworkGate(
            auditRecorder: auditRecorder, consentLookup: StubConsentRecordLookup(meetingsWithConsent: [meetingID]),
            policyLookup: policyLookup, region: .europe, grantTTL: 3600, retentionSeconds: 900)

        let decision = await gate.authorize(
            Self.makeRequest(meetingID: meetingID, purpose: .summarization, classes: [.transcript, .notes]))

        guard case .allowed(let grant) = decision else {
            Issue.record("expected .allowed, got \(decision)")
            return
        }
        #expect(grant.meetingID == meetingID)
        #expect(grant.policyID == policy.policyID)
        #expect(grant.mode == .cloudAllowed)
        #expect(grant.allowedClasses == [.transcript, .notes])
        #expect(grant.capabilities == [.summarization])
        #expect(grant.region == .europe)
        #expect(grant.retentionSeconds == 900)
        #expect(!grant.isExpired(asOf: Date().addingTimeInterval(1800)))
        #expect(grant.isExpired(asOf: Date().addingTimeInterval(3700)))

        let events = await auditRecorder.recordedEvents
        #expect(events.count == 1)
        #expect(events[0].auditEventID == grant.auditEventID)
        #expect(events[0].result == .success)
    }

    @Test func test_missingPolicySnapshot_denies() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let gate = DefaultNetworkGate(
            auditRecorder: SpyAuditEventRecorder(), consentLookup: StubConsentRecordLookup(),
            policyLookup: StubPolicySnapshotLookup())

        let decision = await gate.authorize(Self.makeRequest(meetingID: meetingID))

        guard case .denied(.workspacePolicyBlocked) = decision else {
            Issue.record("expected .denied(.workspacePolicyBlocked), got \(decision)")
            return
        }
    }

    @Test func test_auditLedgerWriteFailure_failsClosed_noGrantIssued() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        await policyLookup.set(Self.makePolicy(mode: .cloudAllowed), for: meetingID)
        let gate = DefaultNetworkGate(
            auditRecorder: SpyAuditEventRecorder(failing: true),
            consentLookup: StubConsentRecordLookup(meetingsWithConsent: [meetingID]), policyLookup: policyLookup)

        let decision = await gate.authorize(Self.makeRequest(meetingID: meetingID))

        guard case .denied(.workspacePolicyBlocked) = decision else {
            Issue.record("expected a fail-closed denial when the audit ledger can't be written, got \(decision)")
            return
        }
    }

    @Test func test_revokeAll_writesAnAuditEvent() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let policyLookup = StubPolicySnapshotLookup()
        await policyLookup.set(Self.makePolicy(mode: .cloudAllowed), for: meetingID)
        let auditRecorder = SpyAuditEventRecorder()
        let gate = DefaultNetworkGate(
            auditRecorder: auditRecorder, consentLookup: StubConsentRecordLookup(meetingsWithConsent: [meetingID]),
            policyLookup: policyLookup)
        _ = await gate.authorize(Self.makeRequest(meetingID: meetingID))

        try await gate.revokeAll(for: meetingID, reason: .userRequested)

        let events = await auditRecorder.recordedEvents
        #expect(events.count == 2)
        #expect(events[1].action == "egress.revokeAll")
    }
}
