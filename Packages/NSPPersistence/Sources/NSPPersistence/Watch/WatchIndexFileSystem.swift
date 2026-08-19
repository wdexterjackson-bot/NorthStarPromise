import Foundation

/// The minimal filesystem primitive `FileBackedWatchLocalStore` needs: read
/// the whole index and atomically replace it (docs/09 NSP-027, "survives
/// app termination"). Unlike `ManifestFileSystem` (`NSPMedia`, NSP-014) this
/// index isn't audio-durability-critical — losing the very last write just
/// means the Watch re-lists what it can still see on disk next launch — so
/// one atomic write-then-rename is enough; it doesn't need WAL-style
/// per-event fsyncs or kill-injection-level step granularity.
public protocol WatchIndexFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func readData(at url: URL) throws -> Data

    /// Writes `data` to a temp file, fsyncs it, then renames it over `url`
    /// — the same tmp→fsync→rename shape as every other durable write in
    /// this codebase (docs/03 §3.2, §3.4), sized down to one call since
    /// there's no WAL phase here.
    func writeAndFsync(_ data: Data, to url: URL) throws
}

/// The real filesystem, backed by `FileHandle` for the fsync and
/// `FileManager` for the atomic rename.
public struct LiveWatchIndexFileSystem: WatchIndexFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeAndFsync(_ data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        if !FileManager.default.fileExists(atPath: tempURL.path) {
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
}
