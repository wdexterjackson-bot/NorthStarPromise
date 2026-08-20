import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `meeting` table (docs/02 §5). `Availability.partial(missing:)`'s
/// array doesn't fit a single column — its rows live in the sibling
/// `meeting_missing_segment` table, synced separately by
/// `GRDBMeetingRepository` (delete-then-reinsert on every write, since the
/// list is always small).
struct MeetingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting"

    var meetingID: String
    var workspaceID: String
    var title: String
    var isTitleSensitive: Bool
    var subtitle: String?
    var calendarEventID: String?
    var captureMode: String
    var originDeviceID: String
    var startedAt: Date
    var endedAt: Date?
    var canonicalDurationSampleCount: Int64
    var canonicalDurationSampleRate: Int
    var lifecycleState: String
    var lifecycleStateFailureReason: String?
    var policyID: String
    var processingMode: String
    var consentRecordID: String?
    var availability: String
    var excludedFromMemory: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowRevision: Int
    var cloudRecordChangeTag: String?

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case workspaceID = "workspace_id"
        case title
        case isTitleSensitive = "is_title_sensitive"
        case subtitle
        case calendarEventID = "calendar_event_id"
        case captureMode = "capture_mode"
        case originDeviceID = "origin_device_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case canonicalDurationSampleCount = "canonical_duration_sample_count"
        case canonicalDurationSampleRate = "canonical_duration_sample_rate"
        case lifecycleState = "lifecycle_state"
        case lifecycleStateFailureReason = "lifecycle_state_failure_reason"
        case policyID = "policy_id"
        case processingMode = "processing_mode"
        case consentRecordID = "consent_record_id"
        case availability
        case excludedFromMemory = "excluded_from_memory"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case rowRevision = "row_revision"
        case cloudRecordChangeTag = "cloud_record_change_tag"
    }

    init(
        meeting: Meeting, createdAt: Date, updatedAt: Date, rowRevision: Int, cloudRecordChangeTag: String?
    ) {
        self.meetingID = meeting.meetingID.rawValue.uuidString
        self.workspaceID = meeting.workspaceID.rawValue.uuidString
        self.title = meeting.title
        self.isTitleSensitive = meeting.isTitleSensitive
        self.subtitle = meeting.subtitle
        self.calendarEventID = meeting.calendarEventID
        self.captureMode = meeting.captureMode.rawValue
        self.originDeviceID = meeting.originDeviceID.rawValue.uuidString
        self.startedAt = meeting.startedAt
        self.endedAt = meeting.endedAt
        self.canonicalDurationSampleCount = meeting.canonicalDuration.sampleCount
        self.canonicalDurationSampleRate = meeting.canonicalDuration.sampleRate
        switch meeting.lifecycleState {
        case .failed(let reason):
            self.lifecycleState = "failed"
            self.lifecycleStateFailureReason = reason
        default:
            self.lifecycleState = Self.lifecycleStateKind(meeting.lifecycleState)
        }
        self.policyID = meeting.policyID.rawValue.uuidString
        self.processingMode = meeting.processingMode.rawValue
        self.consentRecordID = meeting.consentRecordID?.rawValue.uuidString
        switch meeting.availability {
        case .complete: self.availability = "complete"
        case .partial: self.availability = "partial"
        case .recoverable: self.availability = "recoverable"
        case .failed: self.availability = "failed"
        }
        self.excludedFromMemory = meeting.excludedFromMemory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = meeting.deletedAt
        self.rowRevision = rowRevision
        self.cloudRecordChangeTag = cloudRecordChangeTag
    }

    // Every non-payload `MeetingState` case, by name. `.failed` is handled
    // separately by the caller since it's the only case with a payload.
    // swiftlint:disable:next cyclomatic_complexity
    private static func lifecycleStateKind(_ state: MeetingState) -> String {
        switch state {
        case .ready: return "ready"
        case .arming: return "arming"
        case .recording: return "recording"
        case .paused: return "paused"
        case .interrupted: return "interrupted"
        case .finalizing: return "finalizing"
        case .processing: return "processing"
        case .readyForReview: return "readyForReview"
        case .approved: return "approved"
        case .edited: return "edited"
        case .shared: return "shared"
        case .archived: return "archived"
        case .deleted: return "deleted"
        case .restored: return "restored"
        case .purged: return "purged"
        case .recoverable: return "recoverable"
        case .savedRaw: return "savedRaw"
        case .partialFailure: return "partialFailure"
        case .failed: return "failed"
        }
    }

    // `missingSegments` comes from the sibling `meeting_missing_segment`
    // rows — `MeetingRow` alone can't reconstruct `.partial(missing:)`.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func asDomain(missingSegments: [SegmentRef]) throws -> Meeting {
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let captureModeValue = CaptureMode(rawValue: captureMode) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "capture_mode", value: captureMode)
        }
        guard let originDeviceUUID = UUID(uuidString: originDeviceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "origin_device_id", value: originDeviceID)
        }
        guard let policyUUID = UUID(uuidString: policyID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "policy_id", value: policyID)
        }
        guard let processingModeValue = ProcessingMode(rawValue: processingMode) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "processing_mode", value: processingMode)
        }

        let resolvedLifecycleState: MeetingState
        switch lifecycleState {
        case "ready": resolvedLifecycleState = .ready
        case "arming": resolvedLifecycleState = .arming
        case "recording": resolvedLifecycleState = .recording
        case "paused": resolvedLifecycleState = .paused
        case "interrupted": resolvedLifecycleState = .interrupted
        case "finalizing": resolvedLifecycleState = .finalizing
        case "processing": resolvedLifecycleState = .processing
        case "readyForReview": resolvedLifecycleState = .readyForReview
        case "approved": resolvedLifecycleState = .approved
        case "edited": resolvedLifecycleState = .edited
        case "shared": resolvedLifecycleState = .shared
        case "archived": resolvedLifecycleState = .archived
        case "deleted": resolvedLifecycleState = .deleted
        case "restored": resolvedLifecycleState = .restored
        case "purged": resolvedLifecycleState = .purged
        case "recoverable": resolvedLifecycleState = .recoverable
        case "savedRaw": resolvedLifecycleState = .savedRaw
        case "partialFailure": resolvedLifecycleState = .partialFailure
        case "failed": resolvedLifecycleState = .failed(reason: lifecycleStateFailureReason ?? "unknown")
        default:
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "lifecycle_state", value: lifecycleState)
        }

        let resolvedAvailability: Availability
        switch availability {
        case "complete": resolvedAvailability = .complete
        case "partial": resolvedAvailability = .partial(missing: missingSegments)
        case "recoverable": resolvedAvailability = .recoverable
        case "failed": resolvedAvailability = .failed
        default:
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "availability", value: availability)
        }

        let resolvedConsentRecordID: ConsentRecordID? =
            try consentRecordID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "consent_record_id", value: $0)
                }
                return ConsentRecordID(rawValue: uuid)
            }

        return Meeting(
            meetingID: MeetingID(rawValue: meetingUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            title: title,
            isTitleSensitive: isTitleSensitive,
            subtitle: subtitle,
            calendarEventID: calendarEventID,
            captureMode: captureModeValue,
            originDeviceID: DeviceID(rawValue: originDeviceUUID),
            startedAt: startedAt,
            endedAt: endedAt,
            canonicalDuration: SampleDuration(
                sampleCount: canonicalDurationSampleCount, sampleRate: canonicalDurationSampleRate),
            lifecycleState: resolvedLifecycleState,
            policyID: PolicyID(rawValue: policyUUID),
            processingMode: processingModeValue,
            consentRecordID: resolvedConsentRecordID,
            availability: resolvedAvailability,
            excludedFromMemory: excludedFromMemory,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

/// Mirrors `meeting_missing_segment` — the exploded form of
/// `Availability.partial(missing:)`.
struct MeetingMissingSegmentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_missing_segment"

    var meetingID: String
    var segmentID: String
    var deviceID: String
    var sequence: Int

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case segmentID = "segment_id"
        case deviceID = "device_id"
        case sequence
    }

    init(meetingID: String, ref: SegmentRef) {
        self.meetingID = meetingID
        self.segmentID = ref.segmentID.rawValue.uuidString
        self.deviceID = ref.deviceID.rawValue.uuidString
        self.sequence = ref.sequence
    }

    func asDomain() throws -> SegmentRef {
        guard let segmentUUID = UUID(uuidString: segmentID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "segment_id", value: segmentID)
        }
        guard let deviceUUID = UUID(uuidString: deviceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "device_id", value: deviceID)
        }
        return SegmentRef(
            segmentID: SegmentID(rawValue: segmentUUID), deviceID: DeviceID(rawValue: deviceUUID), sequence: sequence
        )
    }
}
