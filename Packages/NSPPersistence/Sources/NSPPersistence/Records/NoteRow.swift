import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `note` table. `originDeviceID`/`consentRecordID` stay `nil`
/// until (if ever) a recording is attached to the note.
struct NoteRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note"

    var noteID: String
    var workspaceID: String
    var title: String
    var originDeviceID: String?
    var consentRecordID: String?
    var startedAt: Date
    var endedAt: Date?
    var canonicalDurationSampleCount: Int64
    var canonicalDurationSampleRate: Int
    var lifecycleState: String
    var lifecycleStateFailureReason: String?
    var policyID: String
    var processingMode: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case workspaceID = "workspace_id"
        case title
        case originDeviceID = "origin_device_id"
        case consentRecordID = "consent_record_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case canonicalDurationSampleCount = "canonical_duration_sample_count"
        case canonicalDurationSampleRate = "canonical_duration_sample_rate"
        case lifecycleState = "lifecycle_state"
        case lifecycleStateFailureReason = "lifecycle_state_failure_reason"
        case policyID = "policy_id"
        case processingMode = "processing_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case rowRevision = "row_revision"
    }

    init(note: Note, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.noteID = note.noteID.rawValue.uuidString
        self.workspaceID = note.workspaceID.rawValue.uuidString
        self.title = note.title
        self.originDeviceID = note.originDeviceID?.rawValue.uuidString
        self.consentRecordID = note.consentRecordID?.rawValue.uuidString
        self.startedAt = note.startedAt
        self.endedAt = note.endedAt
        self.canonicalDurationSampleCount = note.canonicalDuration.sampleCount
        self.canonicalDurationSampleRate = note.canonicalDuration.sampleRate
        switch note.lifecycleState {
        case .failed(let reason):
            self.lifecycleState = "failed"
            self.lifecycleStateFailureReason = reason
        default:
            self.lifecycleState = MeetingStateColumn.kind(note.lifecycleState)
        }
        self.policyID = note.policyID.rawValue.uuidString
        self.processingMode = note.processingMode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = note.deletedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> Note {
        guard let noteUUID = UUID(uuidString: noteID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "note_id", value: noteID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let policyUUID = UUID(uuidString: policyID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "policy_id", value: policyID)
        }
        guard let processingModeValue = ProcessingMode(rawValue: processingMode) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "processing_mode", value: processingMode)
        }
        let resolvedLifecycleState = try MeetingStateColumn.resolve(
            lifecycleState, failureReason: lifecycleStateFailureReason, table: Self.databaseTableName)
        let resolvedOriginDeviceID: DeviceID? =
            try originDeviceID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "origin_device_id", value: $0)
                }
                return DeviceID(rawValue: uuid)
            }
        let resolvedConsentRecordID: ConsentRecordID? =
            try consentRecordID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "consent_record_id", value: $0)
                }
                return ConsentRecordID(rawValue: uuid)
            }

        return Note(
            noteID: NoteID(rawValue: noteUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            title: title,
            originDeviceID: resolvedOriginDeviceID,
            consentRecordID: resolvedConsentRecordID,
            startedAt: startedAt,
            endedAt: endedAt,
            canonicalDuration: SampleDuration(
                sampleCount: canonicalDurationSampleCount, sampleRate: canonicalDurationSampleRate),
            lifecycleState: resolvedLifecycleState,
            policyID: PolicyID(rawValue: policyUUID),
            processingMode: processingModeValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
