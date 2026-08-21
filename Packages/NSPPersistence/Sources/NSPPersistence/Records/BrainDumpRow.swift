import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `brain_dump` table — same `lifecycleState`/`canonicalDuration`
/// encoding as `MeetingRow`, since `BrainDump` reuses `MeetingState`/
/// `SampleDuration` rather than inventing parallel types.
struct BrainDumpRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "brain_dump"

    var brainDumpID: String
    var workspaceID: String
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
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case brainDumpID = "brain_dump_id"
        case workspaceID = "workspace_id"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case rowRevision = "row_revision"
    }

    init(brainDump: BrainDump, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.brainDumpID = brainDump.brainDumpID.rawValue.uuidString
        self.workspaceID = brainDump.workspaceID.rawValue.uuidString
        self.originDeviceID = brainDump.originDeviceID.rawValue.uuidString
        self.startedAt = brainDump.startedAt
        self.endedAt = brainDump.endedAt
        self.canonicalDurationSampleCount = brainDump.canonicalDuration.sampleCount
        self.canonicalDurationSampleRate = brainDump.canonicalDuration.sampleRate
        switch brainDump.lifecycleState {
        case .failed(let reason):
            self.lifecycleState = "failed"
            self.lifecycleStateFailureReason = reason
        default:
            self.lifecycleState = MeetingStateColumn.kind(brainDump.lifecycleState)
        }
        self.policyID = brainDump.policyID.rawValue.uuidString
        self.processingMode = brainDump.processingMode.rawValue
        self.consentRecordID = brainDump.consentRecordID?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = brainDump.deletedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> BrainDump {
        guard let brainDumpUUID = UUID(uuidString: brainDumpID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "brain_dump_id", value: brainDumpID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
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
        let resolvedLifecycleState = try MeetingStateColumn.resolve(
            lifecycleState, failureReason: lifecycleStateFailureReason, table: Self.databaseTableName)
        let resolvedConsentRecordID: ConsentRecordID? =
            try consentRecordID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(
                        table: Self.databaseTableName, column: "consent_record_id", value: $0)
                }
                return ConsentRecordID(rawValue: uuid)
            }

        return BrainDump(
            brainDumpID: BrainDumpID(rawValue: brainDumpUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            originDeviceID: DeviceID(rawValue: originDeviceUUID),
            startedAt: startedAt,
            endedAt: endedAt,
            canonicalDuration: SampleDuration(
                sampleCount: canonicalDurationSampleCount, sampleRate: canonicalDurationSampleRate),
            lifecycleState: resolvedLifecycleState,
            policyID: PolicyID(rawValue: policyUUID),
            processingMode: processingModeValue,
            consentRecordID: resolvedConsentRecordID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
