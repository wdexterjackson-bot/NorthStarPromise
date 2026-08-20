import Foundation
import NSPMedia

/// In-memory `InkAssetFileSystem` so tests never touch a real disk (docs/11
/// §4). `@unchecked Sendable`: all mutable state is guarded by `lock`, same
/// shape as `FakeContainerFileSystem`.
public final class FakeInkAssetFileSystem: InkAssetFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL: Data] = [:]

    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[url] = data
    }

    public func read(from url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let data = storage[url] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }
}
