import NSPCore
import NSPPersistence
import NSPPolicy

/// Uploads a `Segment`'s audio as a `CD_Segment` record + `CKAsset`,
/// deduping by content hash (docs/02 §6: "Assets are immutable and
/// content-addressed — a duplicate upload collapses to the existing
/// asset"). Same I5 gate as `CloudKitSyncCoordinator` — every upload is
/// authorized through `NetworkGate` first, and a dedupe hit skips the
/// gateway entirely rather than skipping the network but still touching it.
public actor CKAssetUploader {
    private let networkGate: any NetworkGate
    private let gateway: any CloudKitGateway
    private let segmentRepository: any SegmentRepository

    public init(
        networkGate: some NetworkGate, gateway: some CloudKitGateway, segmentRepository: some SegmentRepository
    ) {
        self.networkGate = networkGate
        self.gateway = gateway
        self.segmentRepository = segmentRepository
    }

    /// Returns the `cloudAssetRef` to persist on `segment` — either the ref
    /// of an already-uploaded segment sharing this hash (dedupe hit, no
    /// network call at all), or a freshly saved record's own name.
    ///
    /// Safe to call again after an interruption: the record ID is derived
    /// deterministically from `segmentID` (`CloudKitRecordMapper`), so a
    /// retry saves over the same record rather than creating a duplicate —
    /// CloudKit record saves are themselves idempotent by ID. There is no
    /// separate "resume token" to manage.
    public func upload(_ segment: Segment, meeting: Meeting) async throws -> String {
        guard let sha256 = segment.sha256 else {
            throw SyncError.missingField(record: CloudKitRecordType.segment, field: "sha256")
        }

        let existing = try await segmentRepository.findUploaded(sha256: sha256)
        if let existingRef = existing?.cloudAssetRef {
            return existingRef
        }

        let request = EgressRequest(
            meetingID: meeting.meetingID, purpose: .cloudKitSync, classes: [.audio], byteCount: 0,
            payloadSHA256: "", destination: .cloudKit)
        switch await networkGate.authorize(request) {
        case .allowed:
            break
        case .denied(let denial):
            throw SyncError.egressDenied(denial)
        }

        let zoneID = WorkspaceZone.recordZoneID(for: meeting.workspaceID)
        let record = CloudKitRecordMapper.record(for: segment, zoneID: zoneID)
        let saved = try await gateway.save([record])
        guard let savedRecord = saved.first else {
            throw SyncError.missingField(record: CloudKitRecordType.segment, field: "<save result>")
        }
        return savedRecord.recordID.recordName
    }
}
