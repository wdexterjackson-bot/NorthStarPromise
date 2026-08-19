import Foundation
import NSPCore

/// A `Clock` a test fully controls — no wall-clock reads, no flakiness from
/// timing (docs/11 §5). Starts at a fixed instant and only moves when the
/// test calls `advance`.
public final class FakeClock: Clock, @unchecked Sendable {  // all state guarded by `lock`, NSP-009
    private let lock = NSLock()
    private var current: Date

    public init(startingAt date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = date
    }

    public func now() -> Date {
        lock.withLock { current }
    }

    public func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }

    public func set(to date: Date) {
        lock.withLock { current = date }
    }
}
