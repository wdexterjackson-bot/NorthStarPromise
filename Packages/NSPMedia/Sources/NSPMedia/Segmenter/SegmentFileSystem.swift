import CryptoKit
import Foundation

/// The low-level filesystem primitives the atomic close protocol needs
/// (docs/03 §3.2) beyond what `ManifestFileSystem` already covers —
/// fsync-ing and hashing a file an audio encoder wrote to directly, rather
/// than a whole-content replace this package itself performs. Protocol-
/// injected so `Segmenter` tests never touch a real disk (docs/11 §4).
public protocol SegmentFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    /// fsyncs an already-fully-written file — step 2 of the atomic close
    /// protocol, after the encoder's `finishWriting()`.
    func fsync(at url: URL) throws
    /// SHA-256 over the exact bytes that survived the fsync — step 3.
    func sha256(ofFileAt url: URL) throws -> Data
    /// Atomic rename — step 4. Same same-volume `rename(2)` semantics on
    /// APFS as `ManifestFileSystem.renameItem`.
    func renameItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

/// The real filesystem, backed by `FileHandle` for the fsync and
/// `CryptoKit` for the hash.
public struct LiveSegmentFileSystem: SegmentFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func fsync(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// Loads the file fully into memory to hash it — segments are tens of
    /// seconds of mono audio (single-digit megabytes), so this is a
    /// reasonable simplification; a streaming hash is a valid future
    /// optimization for very long segments, not a correctness concern.
    public func sha256(ofFileAt url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return Data(SHA256.hash(data: data))
    }

    public func renameItem(at source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
