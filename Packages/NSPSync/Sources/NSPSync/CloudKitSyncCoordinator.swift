import CloudKit
import NSPCore
import NSPPolicy

/// Every content-bearing write this coordinator makes goes through
/// `NetworkGate.authorize(purpose: .cloudKitSync)` first (docs/01 §3, I5) —
/// including bootstrapping the workspace zone itself, since a zone's mere
/// existence can leak that a workspace has synced content. A `.localOnly`
/// meeting's `authorize` call always denies with `.localOnlyMeeting`
/// (NSP-016), so `gateway` is never touched at all for one — this is the
/// actual mechanism behind NSP-034's "`.localOnly` meetings produce zero
/// CloudKit writes," not a separate check this type has to get right on
/// its own.
public actor CloudKitSyncCoordinator {
    private let networkGate: any NetworkGate
    private let gateway: any CloudKitGateway

    public init(networkGate: some NetworkGate, gateway: some CloudKitGateway) {
        self.networkGate = networkGate
        self.gateway = gateway
    }

    /// Ensures the workspace's custom zone exists (docs/02 §6).
    @discardableResult
    public func bootstrapZone(for meeting: Meeting) async throws -> CKRecordZone {
        _ = try await authorize(meeting: meeting, classes: [])
        return try await gateway.fetchOrCreateZone(WorkspaceZone.recordZoneID(for: meeting.workspaceID))
    }

    /// Writes the `CD_Meeting` record for `meeting`, bootstrapping the zone
    /// first if needed.
    @discardableResult
    public func syncMeeting(_ meeting: Meeting) async throws -> CKRecord {
        _ = try await authorize(meeting: meeting, classes: [.title, .attendees])
        let zoneID = WorkspaceZone.recordZoneID(for: meeting.workspaceID)
        _ = try await gateway.fetchOrCreateZone(zoneID)
        let record = try CloudKitRecordMapper.record(for: meeting, zoneID: zoneID)
        let saved = try await gateway.save([record])
        guard let first = saved.first else {
            throw SyncError.missingField(record: CloudKitRecordType.meeting, field: "<save result>")
        }
        return first
    }

    /// Writes the `CD_Segment` record for `segment`. `meeting` supplies the
    /// authorization context and zone — a `Segment` alone doesn't carry a
    /// `ProcessingMode`.
    @discardableResult
    public func syncSegment(_ segment: Segment, meeting: Meeting) async throws -> CKRecord {
        _ = try await authorize(meeting: meeting, classes: [.audio])
        let zoneID = WorkspaceZone.recordZoneID(for: meeting.workspaceID)
        let record = CloudKitRecordMapper.record(for: segment, zoneID: zoneID)
        let saved = try await gateway.save([record])
        guard let first = saved.first else {
            throw SyncError.missingField(record: CloudKitRecordType.segment, field: "<save result>")
        }
        return first
    }

    /// Writes the `CD_TranscriptTurn` record for `turn`.
    @discardableResult
    public func syncTranscriptTurn(_ turn: TranscriptTurn, meeting: Meeting) async throws -> CKRecord {
        _ = try await authorize(meeting: meeting, classes: [.transcript])
        let zoneID = WorkspaceZone.recordZoneID(for: meeting.workspaceID)
        let record = try CloudKitRecordMapper.record(for: turn, zoneID: zoneID)
        let saved = try await gateway.save([record])
        guard let first = saved.first else {
            throw SyncError.missingField(record: CloudKitRecordType.transcriptTurn, field: "<save result>")
        }
        return first
    }

    private func authorize(meeting: Meeting, classes: Set<ContentClass>) async throws -> ProcessingGrant {
        let request = EgressRequest(
            meetingID: meeting.meetingID, purpose: .cloudKitSync, classes: classes, byteCount: 0,
            payloadSHA256: "", destination: .cloudKit)
        switch await networkGate.authorize(request) {
        case .allowed(let grant): return grant
        case .denied(let denial): throw SyncError.egressDenied(denial)
        }
    }
}
