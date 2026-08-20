import Foundation

/// Writes a note's ink asset bytes durably — write to a temp file, fsync,
/// atomic rename over the destination — the same shape `SegmentFileSystem`
/// uses for audio segments (docs/03 §3.2's atomic close protocol), scaled
/// down: ink isn't part of the manifest's integrity chain (docs/02 §4), so
/// there's no hash or WAL step, just the guarantee that a reader never sees
/// a partially-written `.drawing` file. Protocol-injected so callers never
/// touch `FileManager` directly (docs/11 §4).
public protocol InkAssetFileSystem: Sendable {
    func write(_ data: Data, to url: URL) throws
    func read(from url: URL) throws -> Data
}

public struct LiveInkAssetFileSystem: InkAssetFileSystem {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
