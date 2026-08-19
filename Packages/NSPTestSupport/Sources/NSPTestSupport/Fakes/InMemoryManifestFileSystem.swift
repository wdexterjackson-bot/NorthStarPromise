import Foundation
import NSPMedia

/// In-memory `ManifestFileSystem` for `ManifestWriter` behavior tests that
/// don't need real fsync/rename semantics — fast, no temp-directory cleanup
/// (docs/11 §4, NSP-014). For the kill-injection acceptance test itself, use
/// `KillInjectingManifestFileSystem` wrapping `LiveManifestFileSystem`
/// instead — this fake's "fsync" is a no-op, so it can't prove a real
/// durability ordering.
public final class InMemoryManifestFileSystem: ManifestFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data] = [:]

    public init() {}

    public func fileExists(at url: URL) -> Bool {
        lock.withLock { files[url] != nil }
    }

    public func readData(at url: URL) throws -> Data {
        try lock.withLock {
            guard let data = files[url] else {
                throw ManifestFileSystemError.cannotOpenDirectory(url)
            }
            return data
        }
    }

    public func writeAndFsync(_ data: Data, to url: URL) throws {
        lock.withLock { files[url] = data }
    }

    public func appendAndFsync(_ data: Data, to url: URL) throws {
        lock.withLock { files[url, default: Data()].append(data) }
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            guard let data = files[source] else {
                throw ManifestFileSystemError.cannotOpenDirectory(source)
            }
            files[destination] = data
        }
    }

    public func renameItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            guard let data = files[source] else {
                throw ManifestFileSystemError.cannotOpenDirectory(source)
            }
            files[destination] = data
            files[source] = nil
        }
    }

    public func fsyncDirectory(at url: URL) throws {}

    public func truncate(at url: URL) throws {
        lock.withLock { files[url] = Data() }
    }
}
