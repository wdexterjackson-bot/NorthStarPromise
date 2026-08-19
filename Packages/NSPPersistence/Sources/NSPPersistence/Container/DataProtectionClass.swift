import Foundation

/// A file or directory's Data Protection class (docs/02 §4, docs/06 §4).
/// Decoupled from Foundation's `FileProtectionType` so this type exists on
/// every platform the package builds for — the real protection API is
/// iOS/watchOS-only, which matters because `swift test` runs on the macOS
/// host.
public enum DataProtectionClass: Sendable, Hashable {
    /// Segment files, `manifest.json[.bak]`, `manifest.wal`, and derived
    /// caches — written while the device may be locked. Wrist-down
    /// recording with the screen off *requires* this; `.complete` would
    /// fail the write and violate Invariant I1 (docs/06 §4).
    case completeUnlessOpen

    /// The database, ink, attachments, and staged exports — no need to
    /// write while locked (docs/06 §4).
    case complete

    #if os(iOS) || os(watchOS) || os(tvOS)
        var fileProtectionType: FileProtectionType {
            switch self {
            case .completeUnlessOpen: return .completeUnlessOpen
            case .complete: return .complete
            }
        }
    #endif
}
