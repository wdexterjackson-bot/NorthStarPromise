import NSPCore

/// Higher = more permissive (docs/06 §1.1's implied ordering: `.localOnly`
/// is tightest, `.cloudAllowed` is loosest). Kept private to this file —
/// nothing outside `PolicyAuthority` should reason about mode ordering
/// directly, since that's exactly the rule this type exists to own.
extension ProcessingMode {
    fileprivate var permissiveness: Int {
        switch self {
        case .localOnly: return 0
        case .onDevicePreferred: return 1
        case .cloudAllowed: return 2
        }
    }
}

/// The single authority for freezing and mutating a meeting's `Policy`
/// snapshot (docs/06 §1.1, NSP-015). This is the only sanctioned path in
/// `NSPPolicy` for either action — no other public API in this module
/// mutates a processing mode. Persistence itself is `NSPPersistence`'s
/// `PolicyRepository`; `NSPPolicy` has no I/O dependency, so this type is
/// pure and trivially testable — callers elsewhere in the app are expected
/// to route every mode change through `requestModeChange`, never write to
/// storage directly (that's what "mode cannot be mutated after Arming by
/// any API path" means in practice: this is the API path, and it enforces
/// the rule before anything is persisted).
public enum PolicyAuthority {
    /// Called once, at Arming (docs/02 §3): copies the workspace's current
    /// default policy into a brand-new, meeting-scoped snapshot with its
    /// own `PolicyID`. From this point the snapshot is a value in its own
    /// right — nothing ties it back to the workspace default it was copied
    /// from, so later workspace-policy edits never retroactively loosen an
    /// already-armed meeting (docs/06 §1.1).
    public static func freezeSnapshot(from workspaceDefault: Policy, newPolicyID: PolicyID) -> Policy {
        Policy(
            policyID: newPolicyID,
            workspaceID: workspaceDefault.workspaceID,
            retentionDays: workspaceDefault.retentionDays,
            defaultProcessingMode: workspaceDefault.defaultProcessingMode,
            announcementRequired: workspaceDefault.announcementRequired,
            blockedDomains: workspaceDefault.blockedDomains,
            blockedLocations: workspaceDefault.blockedLocations
        )
    }

    /// The only sanctioned way to change an already-frozen snapshot's
    /// processing mode. Throws `PolicyError.cannotLoosenAfterArming` unless
    /// `proposedMode` is strictly tighter than, or the same as, the
    /// snapshot's current mode.
    ///
    /// Not implemented here: "tightening... takes effect immediately,
    /// cancelling in-flight jobs and enqueuing a receipted purge"
    /// (docs/06 §1.1) — that side effect needs `NSPBackendClient` and the
    /// deletion pipeline (NSP-096, NSP-131…134), neither of which exists
    /// yet. This function only makes the policy decision.
    public static func requestModeChange(on snapshot: Policy, to proposedMode: ProcessingMode) throws -> Policy {
        guard proposedMode.permissiveness <= snapshot.defaultProcessingMode.permissiveness else {
            throw PolicyError.cannotLoosenAfterArming(from: snapshot.defaultProcessingMode, to: proposedMode)
        }
        var tightened = snapshot
        tightened.defaultProcessingMode = proposedMode
        return tightened
    }
}
