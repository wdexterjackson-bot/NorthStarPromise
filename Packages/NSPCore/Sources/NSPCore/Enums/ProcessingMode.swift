/// A meeting's processing scope, frozen at Arming and never mutated after
/// (Invariant I5, docs/02 §2 `Meeting.processingMode`). `NSPPolicy`'s
/// `NetworkGate` is the single choke point that enforces it.
public enum ProcessingMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Zero bytes of this meeting's content ever leave the device.
    case localOnly
    /// On-device processing preferred; cloud used only where the user has
    /// separately opted in for capability gaps (e.g. no on-device model).
    case onDevicePreferred
    /// Cloud processing permitted for this meeting, per policy.
    case cloudAllowed
}
