import NSPCore

/// Shared `MeetingState` ↔ `(lifecycle_state, lifecycle_state_failure_reason)`
/// column encoding — `Meeting`, `BrainDump`, and `Note` all reuse
/// `MeetingState` for their lifecycle (docs: the states involved describe
/// capturing audio, not being a meeting specifically), so this is one place
/// for that mapping instead of three copies of the same switch.
enum MeetingStateColumn {
    // Every non-payload `MeetingState` case, by name. `.failed` is handled
    // separately by the caller since it's the only case with a payload.
    // swiftlint:disable:next cyclomatic_complexity
    static func kind(_ state: MeetingState) -> String {
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

    // swiftlint:disable:next cyclomatic_complexity
    static func resolve(_ kind: String, failureReason: String?, table: String) throws -> MeetingState {
        switch kind {
        case "ready": return .ready
        case "arming": return .arming
        case "recording": return .recording
        case "paused": return .paused
        case "interrupted": return .interrupted
        case "finalizing": return .finalizing
        case "processing": return .processing
        case "readyForReview": return .readyForReview
        case "approved": return .approved
        case "edited": return .edited
        case "shared": return .shared
        case "archived": return .archived
        case "deleted": return .deleted
        case "restored": return .restored
        case "purged": return .purged
        case "recoverable": return .recoverable
        case "savedRaw": return .savedRaw
        case "partialFailure": return .partialFailure
        case "failed": return .failed(reason: failureReason ?? "unknown")
        default:
            throw PersistenceError.corruptRow(table: table, column: "lifecycle_state", value: kind)
        }
    }
}
