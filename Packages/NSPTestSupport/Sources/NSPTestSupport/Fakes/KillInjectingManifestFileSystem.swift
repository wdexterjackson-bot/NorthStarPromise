import Foundation
import NSPMedia

/// Wraps a real `ManifestFileSystem` and fails exactly one write-ish
/// operation — simulating the process dying at that instant, before that
/// operation's effect ever reached disk (NSP-014's kill-injection
/// acceptance). Reads (`fileExists`, `readData`) are never killed: they
/// have no durability consequence, so a "crash during a read" isn't a
/// meaningful scenario to test.
///
/// Wrap `LiveManifestFileSystem` over a real temp directory, not
/// `InMemoryManifestFileSystem` — the point of this test is to prove the
/// *ordering* of real fsyncs and renames is safe, and an in-memory fake's
/// no-op fsync can't demonstrate that.
public final class KillInjectingManifestFileSystem: ManifestFileSystem, @unchecked Sendable {
    public struct KillInjected: Error, Sendable, Hashable {
        public let step: Int
    }

    private let lock = NSLock()
    private let wrapped: any ManifestFileSystem
    private var stepCount = 0
    private let killAtStep: Int?

    /// - Parameter killAtStep: The 1-indexed write-ish operation to fail at.
    ///   `nil` runs every operation for real — use this first, on a fresh
    ///   instance, to measure how many steps a script produces.
    public init(wrapping wrapped: any ManifestFileSystem, killAtStep: Int? = nil) {
        self.wrapped = wrapped
        self.killAtStep = killAtStep
    }

    /// How many write-ish operations have been attempted so far. Run a
    /// script once with `killAtStep: nil` and read this afterward to learn
    /// the total step count before running the exhaustive kill loop.
    public var stepsAttempted: Int {
        lock.withLock { stepCount }
    }

    private func step<T>(_ operation: () throws -> T) throws -> T {
        let currentStep: Int = lock.withLock {
            stepCount += 1
            return stepCount
        }
        if currentStep == killAtStep {
            throw KillInjected(step: currentStep)
        }
        return try operation()
    }

    public func fileExists(at url: URL) -> Bool {
        wrapped.fileExists(at: url)
    }

    public func readData(at url: URL) throws -> Data {
        try wrapped.readData(at: url)
    }

    public func writeAndFsync(_ data: Data, to url: URL) throws {
        try step { try wrapped.writeAndFsync(data, to: url) }
    }

    public func appendAndFsync(_ data: Data, to url: URL) throws {
        try step { try wrapped.appendAndFsync(data, to: url) }
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try step { try wrapped.copyItem(at: source, to: destination) }
    }

    public func renameItem(at source: URL, to destination: URL) throws {
        try step { try wrapped.renameItem(at: source, to: destination) }
    }

    public func fsyncDirectory(at url: URL) throws {
        try step { try wrapped.fsyncDirectory(at: url) }
    }

    public func truncate(at url: URL) throws {
        try step { try wrapped.truncate(at: url) }
    }
}
