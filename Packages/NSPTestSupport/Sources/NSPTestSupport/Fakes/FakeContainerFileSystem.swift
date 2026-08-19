import Foundation
import NSPPersistence

/// Records every directory it was asked to create, and the protection class
/// requested for it, without touching the real disk (docs/11 §4, NSP-013).
/// `ContainerFileSystem`'s methods are synchronous, so a lock — not an
/// actor — is the right tool here.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`. NSP-013.
public final class FakeContainerFileSystem: ContainerFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var createdDirectories: [URL: DataProtectionClass] = [:]

    public init() {}

    public func createDirectory(at url: URL, protection: DataProtectionClass) throws {
        lock.lock()
        defer { lock.unlock() }
        createdDirectories[url] = protection
    }

    public func fileExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return createdDirectories[url] != nil
    }

    public func protection(at url: URL) -> DataProtectionClass? {
        lock.lock()
        defer { lock.unlock() }
        return createdDirectories[url]
    }
}
