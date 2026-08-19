import Foundation
import NSPCore

/// The single entry point to the network for meeting content (docs/01 §3,
/// docs/06 §2, I5). Nothing outside `NSPPolicy` may construct a
/// `ProcessingGrant` (POL-002); every caller elsewhere in the app —
/// `NSPIntelligence`'s remote transcription/summarization paths, `NSPSync`'s
/// CloudKit writes, `NSPActions`'s share links and integration writes — must
/// go through `authorize` first, every time, for every request.
public protocol NetworkGate: Sendable {
    /// Emits exactly one `AuditEvent` per call, whether the result is
    /// `.allowed` or `.denied` (docs/06 §2) — the audit ledger is the record
    /// of *every* egress decision, not just the approved ones.
    func authorize(_ request: EgressRequest) async -> EgressDecision

    /// Invalidates every grant this gate has issued for `meetingID`. Only
    /// the in-process bookkeeping and audit trail are handled here — actually
    /// cancelling jobs already in flight at the processing plane needs
    /// `NSPBackendClient`, which doesn't exist yet (same scope limitation as
    /// `PolicyAuthority.requestModeChange`, docs/06 §1.1).
    func revokeAll(for meetingID: MeetingID, reason: RevocationReason) async throws
}

/// The production `NetworkGate`. An actor so the in-memory issued-grant
/// registry it needs for `revokeAll` is safe to mutate from concurrent
/// `authorize` calls without a separate lock.
public actor DefaultNetworkGate: NetworkGate {
    private let auditRecorder: AuditEventRecorder
    private let consentLookup: ConsentRecordLookup
    private let policyLookup: PolicySnapshotLookup
    private let region: ProcessingRegion
    private let grantTTL: TimeInterval
    private let retentionSeconds: Int

    private var issuedGrantIDs: [MeetingID: Set<GrantID>] = [:]

    /// - Parameters:
    ///   - grantTTL: Default 6 hours — docs/05 §3.1's `notAfter (≤ 6h)`.
    ///   - retentionSeconds: Default 24 hours — docs/05 §3.3's processing-copy TTL.
    public init(
        auditRecorder: AuditEventRecorder,
        consentLookup: ConsentRecordLookup,
        policyLookup: PolicySnapshotLookup,
        region: ProcessingRegion = .unitedStates,
        grantTTL: TimeInterval = 6 * 3600,
        retentionSeconds: Int = 24 * 3600
    ) {
        self.auditRecorder = auditRecorder
        self.consentLookup = consentLookup
        self.policyLookup = policyLookup
        self.region = region
        self.grantTTL = grantTTL
        self.retentionSeconds = retentionSeconds
    }

    public func authorize(_ request: EgressRequest) async -> EgressDecision {
        guard let policy = await policyLookup.policy(for: request.meetingID) else {
            return await deny(.workspacePolicyBlocked(reason: "no policy snapshot for meeting"), request: request)
        }

        switch policy.defaultProcessingMode {
        case .localOnly:
            // docs/06 §1.1: the only permitted egress under .localOnly is
            // WatchConnectivity relay and user-initiated export, neither of
            // which is content leaving to a network service — neither goes
            // through NetworkGate at all, so every call reaching here denies.
            return await deny(.localOnlyMeeting, request: request)

        case .onDevicePreferred:
            // docs/06 §1.1: CloudKit private-DB writes are permitted (the
            // user's own iCloud, not a processing plane); cloud ASR/
            // summarization/share-links/integrations are forbidden without
            // an explicit per-meeting upgrade, which changes the frozen
            // Policy itself via PolicyAuthority rather than bypassing this
            // gate — so anything but cloudKitSync denies here.
            guard request.purpose == .cloudKitSync else {
                return await deny(
                    .workspacePolicyBlocked(
                        reason: "onDevicePreferred forbids cloud processing without an explicit per-meeting upgrade"),
                    request: request)
            }

        case .cloudAllowed:
            break
        }

        guard await consentLookup.hasConsentRecord(for: request.meetingID) else {
            return await deny(.noConsentRecord, request: request)
        }

        return await allow(request: request, policy: policy)
    }

    public func revokeAll(for meetingID: MeetingID, reason: RevocationReason) async throws {
        let revokedCount = issuedGrantIDs.removeValue(forKey: meetingID)?.count ?? 0
        let event = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()),
            actorID: nil,
            action: "egress.revokeAll",
            object: "meeting:\(meetingID.rawValue.uuidString):reason:\(reason):grants:\(revokedCount)",
            payloadHash: "",
            result: .success,
            timestamp: Date()
        )
        try await auditRecorder.record(event)
    }

    private func allow(request: EgressRequest, policy: Policy) async -> EgressDecision {
        let now = Date()
        let auditEventID = AuditEventID(rawValue: UUID())
        let event = AuditEvent(
            auditEventID: auditEventID,
            actorID: nil,
            action: "egress.authorize",
            object: "meeting:\(request.meetingID.rawValue.uuidString)",
            payloadHash: request.payloadSHA256,
            result: .success,
            timestamp: now
        )

        do {
            try await auditRecorder.record(event)
        } catch {
            // Fail closed (I1 durability-before-ack, I4 evidence-required):
            // without a durable audit entry there is no record this egress
            // happened, so the egress must not happen either.
            return .denied(.workspacePolicyBlocked(reason: "audit ledger write failed"))
        }

        let grant = ProcessingGrant(
            grantID: GrantID(rawValue: UUID()),
            meetingID: request.meetingID,
            policyID: policy.policyID,
            mode: policy.defaultProcessingMode,
            allowedClasses: request.classes,
            capabilities: Self.capabilities(for: request.purpose),
            expiresAt: now.addingTimeInterval(grantTTL),
            region: region,
            retentionSeconds: retentionSeconds,
            auditEventID: auditEventID
        )
        issuedGrantIDs[request.meetingID, default: []].insert(grant.grantID)
        return .allowed(grant)
    }

    private func deny(_ denial: EgressDenial, request: EgressRequest) async -> EgressDecision {
        let event = AuditEvent(
            auditEventID: AuditEventID(rawValue: UUID()),
            actorID: nil,
            action: "egress.authorize",
            object: "meeting:\(request.meetingID.rawValue.uuidString)",
            payloadHash: request.payloadSHA256,
            result: .denied,
            timestamp: Date()
        )
        try? await auditRecorder.record(event)
        return .denied(denial)
    }

    private static func capabilities(for purpose: EgressPurpose) -> Set<ProcessingCapability> {
        switch purpose {
        case .transcription: return [.streamingASR, .batchASR]
        case .diarization: return [.diarization]
        case .summarization: return [.summarization]
        case .retrievalIndex: return [.embedding, .entailment]
        case .cloudKitSync, .shareLink, .integrationWrite, .diagnosticsBundle: return []
        }
    }
}
