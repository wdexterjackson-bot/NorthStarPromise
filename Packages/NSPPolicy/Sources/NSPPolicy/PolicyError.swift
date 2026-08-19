import NSPCore

/// Typed, exhaustive error enum for `NSPPolicy` (docs/11 §2).
public enum PolicyError: Error, Sendable, Hashable {
    /// Post-Arming, a meeting's processing mode may only tighten
    /// (`.cloudAllowed` → `.onDevicePreferred` → `.localOnly`), never
    /// loosen — docs/06 §1.1. Loosening after Arming is rejected outright,
    /// by no API path in this module.
    case cannotLoosenAfterArming(from: ProcessingMode, to: ProcessingMode)
}

extension PolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cannotLoosenAfterArming(let from, let to):
            return "Cannot change processing mode from \(from) to \(to) after Arming — that would loosen it"
        }
    }
}
