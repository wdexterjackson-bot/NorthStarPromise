import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `policy` table (docs/02 §5). Every armed meeting gets its own
/// row — a frozen snapshot, never the workspace's live default — per
/// docs/06 §1.1; `blockedDomains`/`blockedLocations` live in their own
/// child tables since they're arrays.
struct PolicyRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "policy"

    var policyID: String
    var workspaceID: String
    var retentionDays: Int?
    var defaultProcessingMode: String
    var announcementRequired: Bool
    var ambientModeEnabled: Bool
    var ambientSessionDurationMinutes: Int
    var onboardingState: String
    var onboardingLastStepIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int
    var cloudRecordChangeTag: String?

    enum CodingKeys: String, CodingKey {
        case policyID = "policy_id"
        case workspaceID = "workspace_id"
        case retentionDays = "retention_days"
        case defaultProcessingMode = "default_processing_mode"
        case announcementRequired = "announcement_required"
        case ambientModeEnabled = "ambient_mode_enabled"
        case ambientSessionDurationMinutes = "ambient_session_duration_minutes"
        case onboardingState = "onboarding_state"
        case onboardingLastStepIndex = "onboarding_last_step_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
        case cloudRecordChangeTag = "cloud_record_change_tag"
    }

    init(policy: Policy, createdAt: Date, updatedAt: Date, rowRevision: Int, cloudRecordChangeTag: String?) {
        self.policyID = policy.policyID.rawValue.uuidString
        self.workspaceID = policy.workspaceID.rawValue.uuidString
        self.retentionDays = policy.retentionDays
        self.defaultProcessingMode = policy.defaultProcessingMode.rawValue
        self.announcementRequired = policy.announcementRequired
        self.ambientModeEnabled = policy.ambientModeEnabled
        self.ambientSessionDurationMinutes = policy.ambientSessionDurationMinutes
        self.onboardingState = policy.onboardingState.rawValue
        self.onboardingLastStepIndex = policy.onboardingLastStepIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
        self.cloudRecordChangeTag = cloudRecordChangeTag
    }

    func asDomain(blockedDomains: [String], blockedLocations: [String], ambientTrustedLocations: [String]) throws -> Policy {
        guard let policyUUID = UUID(uuidString: policyID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "policy_id", value: policyID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let mode = ProcessingMode(rawValue: defaultProcessingMode) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "default_processing_mode", value: defaultProcessingMode)
        }
        guard let resolvedOnboardingState = OnboardingState(rawValue: onboardingState) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "onboarding_state", value: onboardingState)
        }

        return Policy(
            policyID: PolicyID(rawValue: policyUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            retentionDays: retentionDays,
            defaultProcessingMode: mode,
            announcementRequired: announcementRequired,
            blockedDomains: blockedDomains,
            blockedLocations: blockedLocations,
            ambientModeEnabled: ambientModeEnabled,
            ambientTrustedLocations: ambientTrustedLocations,
            ambientSessionDurationMinutes: ambientSessionDurationMinutes,
            onboardingState: resolvedOnboardingState,
            onboardingLastStepIndex: onboardingLastStepIndex
        )
    }
}

struct PolicyAmbientTrustedLocationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "policy_ambient_trusted_location"
    var policyID: String
    var position: Int
    var location: String

    enum CodingKeys: String, CodingKey {
        case policyID = "policy_id"
        case position
        case location
    }
}

/// Mirrors `policy_blocked_domain` / `policy_blocked_location` — the
/// exploded form of `Policy.blockedDomains` / `.blockedLocations`.
struct PolicyBlockedDomainRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "policy_blocked_domain"
    var policyID: String
    var position: Int
    var domain: String

    enum CodingKeys: String, CodingKey {
        case policyID = "policy_id"
        case position
        case domain
    }
}

struct PolicyBlockedLocationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "policy_blocked_location"
    var policyID: String
    var position: Int
    var location: String

    enum CodingKeys: String, CodingKey {
        case policyID = "policy_id"
        case position
        case location
    }
}
