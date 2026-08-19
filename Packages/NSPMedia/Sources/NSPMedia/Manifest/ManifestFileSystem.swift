import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Typed, exhaustive error enum for the low-level manifest filesystem
/// operations (docs/11 §2).
public enum ManifestFileSystemError: Error, Sendable, Hashable {
    case cannotOpenDirectory(URL)
    case fsyncFailed(URL)
}

/// The exact low-level filesystem primitives `ManifestWriter` needs to
/// implement the WAL-append and seal protocols (docs/03 §3.2, §3.4)
/// step-by-step, protocol-injected so a test can fail any single step in
/// isolation (NSP-014's kill-injection acceptance) without touching a real
/// disk. Every method is one durability-relevant unit — never combine two
/// of these into one call, or a kill point disappears.
public protocol ManifestFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func readData(at url: URL) throws -> Data

    /// Replaces the full contents of `url` (creating it if needed) and
    /// fsyncs — used for `manifest.json.tmp` (docs/03 §3.4 step 1).
    func writeAndFsync(_ data: Data, to url: URL) throws

    /// Appends `data` to `url` (creating it if needed) and fsyncs — used for
    /// every `manifest.wal` entry (docs/03 §3.2 step 5).
    func appendAndFsync(_ data: Data, to url: URL) throws

    /// Overwrites `destination` with `source`'s current contents — the
    /// `.bak` rotation (docs/03 §3.4).
    func copyItem(at source: URL, to destination: URL) throws

    /// Atomically replaces `destination` with `source` (docs/03 §3.2 step 4,
    /// §3.4) — same-volume `rename(2)` on APFS.
    func renameItem(at source: URL, to destination: URL) throws

    /// fsyncs the directory entry itself, so the rename above is durable,
    /// not just visible (docs/03 §3.4).
    func fsyncDirectory(at url: URL) throws

    /// Empties `url` in place — "truncate `manifest.wal`" (docs/03 §3.4).
    func truncate(at url: URL) throws
}

/// The real filesystem, backed by `FileHandle` for data I/O and a raw
/// `fsync(2)` call for the directory entry (Foundation has no portable way
/// to fsync a directory). Every method here is deliberately unsafe to call
/// with `try?` — a swallowed error on this path means a lost meeting
/// (`CLAUDE.md` §5.6).
public struct LiveManifestFileSystem: ManifestFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeAndFsync(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    public func appendAndFsync(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func renameItem(at source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func fsyncDirectory(at url: URL) throws {
        #if canImport(Darwin)
            let descriptor = open(url.path, O_RDONLY)
            guard descriptor >= 0 else { throw ManifestFileSystemError.cannotOpenDirectory(url) }
            defer { close(descriptor) }
            guard fsync(descriptor) == 0 else { throw ManifestFileSystemError.fsyncFailed(url) }
        #endif
    }

    public func truncate(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.synchronize()
    }
}
