import Foundation

/// The filesystem operations `MeetingContainer` needs, protocol-injected so
/// tests never touch the real disk outside a temp dir (docs/11 §4, §5).
public protocol ContainerFileSystem: Sendable {
    func createDirectory(at url: URL, protection: DataProtectionClass) throws
    func fileExists(at url: URL) -> Bool
    /// Removes a meeting's whole on-disk directory tree — segments, ink,
    /// attachments, derived files — after its DB rows are already gone
    /// (meeting deletion; the DB delete, not this, is the source of truth
    /// for "the meeting is gone"). A no-op if nothing exists at `url`.
    func removeDirectory(at url: URL) throws
}

/// The real filesystem, backed by `FileManager`. Sets Data Protection via
/// `FileProtectionType` on iOS/watchOS/tvOS; a no-op attribute elsewhere,
/// since macOS (where `swift test` runs) has no per-file protection API —
/// FileVault covers that at the volume level instead.
public struct LiveContainerFileSystem: ContainerFileSystem {
    public init() {}

    public func createDirectory(at url: URL, protection: DataProtectionClass) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS) || os(tvOS)
            try fileManager.setAttributes(
                [.protectionKey: protection.fileProtectionType], ofItemAtPath: url.path)
        #endif
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func removeDirectory(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
