import CloudKit
import Foundation
import NSPCore
import NSPPolicy

/// Typed, exhaustive error enum for `NSPSync` (docs/11 §2).
public enum SyncError: Error, Sendable, Hashable {
    case egressDenied(EgressDenial)
    case missingField(record: String, field: String)
    case malformedField(record: String, field: String)
}

extension CKRecord {
    /// JSON-encodes `value` into `field` — for the handful of domain enums
    /// with associated values (`MeetingState`, `Availability`,
    /// `TransferState`, `EditState`...) that have no natural single
    /// `CKRecordValue` representation. `Data` is itself a native
    /// `CKRecordValue`, so this is a real, storable field, not a workaround.
    func setJSON<T: Encodable>(_ value: T, forKey field: String) throws {
        self[field] = try JSONEncoder().encode(value) as CKRecordValue
    }

    func decodeJSON<T: Decodable>(_ type: T.Type, forKey field: String, recordType: String) throws -> T {
        guard let data = self[field] as? Data else {
            throw SyncError.missingField(record: recordType, field: field)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requiredString(forKey field: String, recordType: String) throws -> String {
        guard let value = self[field] as? String else {
            throw SyncError.missingField(record: recordType, field: field)
        }
        return value
    }

    func requiredDate(forKey field: String, recordType: String) throws -> Date {
        guard let value = self[field] as? Date else {
            throw SyncError.missingField(record: recordType, field: field)
        }
        return value
    }

    func requiredUUID(forKey field: String, recordType: String) throws -> UUID {
        guard let value = UUID(uuidString: try requiredString(forKey: field, recordType: recordType)) else {
            throw SyncError.malformedField(record: recordType, field: field)
        }
        return value
    }
}

/// Maps `Meeting`/`Segment`/`TranscriptTurn` to and from the `CD_*` record
/// shapes in docs/02 §6. `Segment`'s `CKAsset` upload and content-addressed
/// dedupe by `sha256` is NSP-035's job — this only attaches the asset when
/// a local file is already known.
public enum CloudKitRecordMapper {
    // MARK: - Content owner (Meeting / BrainDump / Note)

    /// `segment`/`transcript_turn` sync only ever carries a `Meeting` owner
    /// today — `Note`/`BrainDump` have no sync scaffolding yet, matching
    /// `Action`/`Decision`/`NSPThread`'s own not-yet-synced state. Still
    /// encodes the real `ownerKind` (not just the meeting id) so a future
    /// sync pass for the other two owner kinds is additive, not another
    /// migration of already-synced records.
    static func encodeOwner(_ owner: ContentOwnerRef) -> (id: String, kind: String) {
        switch owner {
        case .meeting(let id): return (id.rawValue.uuidString, "meeting")
        case .brainDump(let id): return (id.rawValue.uuidString, "brainDump")
        case .note(let id): return (id.rawValue.uuidString, "note")
        }
    }

    static func decodeOwner(id: UUID, kind: String, recordType: String) throws -> ContentOwnerRef {
        switch kind {
        case "meeting": return .meeting(MeetingID(rawValue: id))
        case "brainDump": return .brainDump(BrainDumpID(rawValue: id))
        case "note": return .note(NoteID(rawValue: id))
        default: throw SyncError.malformedField(record: recordType, field: "ownerKind")
        }
    }

    // MARK: - Meeting

    public static func recordID(for meetingID: MeetingID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: meetingID.rawValue.uuidString, zoneID: zoneID)
    }

    /// `title` is written through `encryptedValues` — docs/02 §6: "sensitive
    /// fields (title, notes text) use encrypted fields."
    public static func record(for meeting: Meeting, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitRecordType.meeting, recordID: recordID(for: meeting.meetingID, zoneID: zoneID))

        record.encryptedValues["title"] = meeting.title
        record["isTitleSensitive"] = meeting.isTitleSensitive as CKRecordValue
        record["calendarEventID"] = meeting.calendarEventID as CKRecordValue?
        record["workspaceID"] = meeting.workspaceID.rawValue.uuidString as CKRecordValue
        record["captureMode"] = meeting.captureMode.rawValue as CKRecordValue
        record["originDeviceID"] = meeting.originDeviceID.rawValue.uuidString as CKRecordValue
        record["startedAt"] = meeting.startedAt as CKRecordValue
        record["endedAt"] = meeting.endedAt as CKRecordValue?
        record["canonicalDurationSampleCount"] = meeting.canonicalDuration.sampleCount as CKRecordValue
        record["canonicalDurationSampleRate"] = Int64(meeting.canonicalDuration.sampleRate) as CKRecordValue
        try record.setJSON(meeting.lifecycleState, forKey: "lifecycleStateJSON")
        record["policyID"] = meeting.policyID.rawValue.uuidString as CKRecordValue
        record["processingMode"] = meeting.processingMode.rawValue as CKRecordValue
        record["consentRecordID"] = meeting.consentRecordID?.rawValue.uuidString as CKRecordValue?
        try record.setJSON(meeting.availability, forKey: "availabilityJSON")
        record["excludedFromMemory"] = meeting.excludedFromMemory as CKRecordValue
        record["createdAt"] = meeting.createdAt as CKRecordValue
        record["updatedAt"] = meeting.updatedAt as CKRecordValue
        record["deletedAt"] = meeting.deletedAt as CKRecordValue?

        return record
    }

    public static func meeting(from record: CKRecord) throws -> Meeting {
        guard let title = record.encryptedValues["title"] as? String else {
            throw SyncError.missingField(record: CloudKitRecordType.meeting, field: "title")
        }
        guard let meetingUUID = UUID(uuidString: record.recordID.recordName) else {
            throw SyncError.malformedField(record: CloudKitRecordType.meeting, field: "recordID")
        }
        let recordType = CloudKitRecordType.meeting
        let workspaceUUID = try record.requiredUUID(forKey: "workspaceID", recordType: recordType)
        let originDeviceUUID = try record.requiredUUID(forKey: "originDeviceID", recordType: recordType)
        let policyUUID = try record.requiredUUID(forKey: "policyID", recordType: recordType)
        guard
            let captureMode = CaptureMode(
                rawValue: try record.requiredString(forKey: "captureMode", recordType: recordType)),
            let processingMode = ProcessingMode(
                rawValue: try record.requiredString(forKey: "processingMode", recordType: recordType))
        else {
            throw SyncError.malformedField(record: CloudKitRecordType.meeting, field: "<multiple>")
        }
        guard let sampleCount = record["canonicalDurationSampleCount"] as? Int64,
            let sampleRate = record["canonicalDurationSampleRate"] as? Int64
        else {
            throw SyncError.missingField(record: CloudKitRecordType.meeting, field: "canonicalDuration")
        }
        let consentRecordIDString = record["consentRecordID"] as? String

        return Meeting(
            meetingID: MeetingID(rawValue: meetingUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            title: title,
            isTitleSensitive: (record["isTitleSensitive"] as? Bool) ?? false,
            calendarEventID: record["calendarEventID"] as? String,
            captureMode: captureMode,
            originDeviceID: DeviceID(rawValue: originDeviceUUID),
            startedAt: try record.requiredDate(forKey: "startedAt", recordType: CloudKitRecordType.meeting),
            endedAt: record["endedAt"] as? Date,
            canonicalDuration: SampleDuration(sampleCount: sampleCount, sampleRate: Int(sampleRate)),
            lifecycleState: try record.decodeJSON(
                MeetingState.self, forKey: "lifecycleStateJSON", recordType: CloudKitRecordType.meeting),
            policyID: PolicyID(rawValue: policyUUID),
            processingMode: processingMode,
            consentRecordID: consentRecordIDString.flatMap { UUID(uuidString: $0) }.map {
                ConsentRecordID(rawValue: $0)
            },
            availability: try record.decodeJSON(
                Availability.self, forKey: "availabilityJSON", recordType: CloudKitRecordType.meeting),
            excludedFromMemory: (record["excludedFromMemory"] as? Bool) ?? false,
            createdAt: try record.requiredDate(forKey: "createdAt", recordType: CloudKitRecordType.meeting),
            updatedAt: try record.requiredDate(forKey: "updatedAt", recordType: CloudKitRecordType.meeting),
            deletedAt: record["deletedAt"] as? Date)
    }

    // MARK: - Segment

    public static func recordID(for segmentID: SegmentID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: segmentID.rawValue.uuidString, zoneID: zoneID)
    }

    public static func record(for segment: Segment, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitRecordType.segment, recordID: recordID(for: segment.segmentID, zoneID: zoneID))

        let owner = Self.encodeOwner(segment.owner)
        record["meetingID"] = owner.id as CKRecordValue
        record["ownerKind"] = owner.kind as CKRecordValue
        record["deviceID"] = segment.deviceID.rawValue.uuidString as CKRecordValue
        record["sequence"] = segment.sequence as CKRecordValue
        record["codec"] = segment.codec.rawValue as CKRecordValue
        record["sampleRate"] = segment.sampleRate as CKRecordValue
        record["channels"] = segment.channels as CKRecordValue
        record["bitRate"] = segment.bitRate as CKRecordValue
        record["startSample"] = segment.startSample as CKRecordValue
        record["sampleCount"] = segment.sampleCount as CKRecordValue
        record["sha256"] = segment.sha256 as CKRecordValue?
        record["cloudAssetRef"] = segment.cloudAssetRef as CKRecordValue?
        record["transferStateJSON"] = try? JSONEncoder().encode(segment.transferState) as CKRecordValue?
        record["isRepairedTail"] = segment.isRepairedTail as CKRecordValue

        // Content-addressed dedupe against an existing asset is NSP-035's
        // job; this only attaches the file that's already known locally.
        if let localURL = segment.localURL {
            record["audio"] = CKAsset(fileURL: localURL)
        }

        return record
    }

    /// `localURL` is never a synced field — it's meaningless across devices
    /// — so a freshly decoded `Segment` always has `localURL == nil`, which
    /// is exactly the signal `MeetingAvailabilityReconciler` needs: audio
    /// hasn't downloaded to *this* device yet, even though the metadata has.
    public static func segment(from record: CKRecord) throws -> Segment {
        let recordType = CloudKitRecordType.segment
        guard let segmentUUID = UUID(uuidString: record.recordID.recordName) else {
            throw SyncError.malformedField(record: recordType, field: "recordID")
        }
        let meetingUUID = try record.requiredUUID(forKey: "meetingID", recordType: recordType)
        // Absent on a record synced before `ownerKind` existed — every such
        // record predates `Note`/`BrainDump`, so `.meeting` is the correct
        // (not merely default) reading, not a guess.
        let ownerKind = (record["ownerKind"] as? String) ?? "meeting"
        let owner = try Self.decodeOwner(id: meetingUUID, kind: ownerKind, recordType: recordType)
        let deviceUUID = try record.requiredUUID(forKey: "deviceID", recordType: recordType)
        guard let codec = AudioCodec(rawValue: try record.requiredString(forKey: "codec", recordType: recordType))
        else {
            throw SyncError.malformedField(record: recordType, field: "codec")
        }
        guard let sequence = record["sequence"] as? Int, let sampleRate = record["sampleRate"] as? Int,
            let channels = record["channels"] as? Int, let bitRate = record["bitRate"] as? Int,
            let startSample = record["startSample"] as? Int64, let sampleCount = record["sampleCount"] as? Int64
        else {
            throw SyncError.missingField(record: recordType, field: "<multiple>")
        }
        let transferState =
            (record["transferStateJSON"] as? Data).flatMap { try? JSONDecoder().decode(TransferState.self, from: $0) }
            ?? .local

        return Segment(
            segmentID: SegmentID(rawValue: segmentUUID), owner: owner,
            deviceID: DeviceID(rawValue: deviceUUID), sequence: sequence, codec: codec, sampleRate: sampleRate,
            channels: channels, bitRate: bitRate, startSample: startSample, sampleCount: sampleCount,
            sha256: record["sha256"] as? Data, localURL: nil, cloudAssetRef: record["cloudAssetRef"] as? String,
            transferState: transferState, isRepairedTail: (record["isRepairedTail"] as? Bool) ?? false)
    }

    // MARK: - TranscriptTurn

    public static func recordID(for turnID: TranscriptTurnID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: turnID.rawValue.uuidString, zoneID: zoneID)
    }

    public static func record(for turn: TranscriptTurn, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitRecordType.transcriptTurn, recordID: recordID(for: turn.turnID, zoneID: zoneID))

        let owner = Self.encodeOwner(turn.owner)
        record["meetingID"] = owner.id as CKRecordValue
        record["ownerKind"] = owner.kind as CKRecordValue
        record["revision"] = turn.revision as CKRecordValue
        record["isProvisional"] = turn.isProvisional as CKRecordValue
        record["speakerClusterID"] = turn.speakerClusterID as CKRecordValue?
        record["personID"] = turn.personID?.rawValue.uuidString as CKRecordValue?
        try record.setJSON(turn.tokens, forKey: "tokensJSON")
        try record.setJSON(turn.languageSpans, forKey: "languageSpansJSON")
        record["segmentRefs"] = turn.segmentRefs.map(\.rawValue.uuidString) as CKRecordValue
        try record.setJSON(turn.editState, forKey: "editStateJSON")

        return record
    }
}
