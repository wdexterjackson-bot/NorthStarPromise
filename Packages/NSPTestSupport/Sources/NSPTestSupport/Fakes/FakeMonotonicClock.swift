import Foundation
import NSPCore

/// A `MonotonicClock` a test fully controls, for exercising backoff/timeout
/// math without real sleeps (docs/11 §5: "no sleep, no wall-clock waits —
/// advance FakeClock").
public final class FakeMonotonicClock: MonotonicClock, @unchecked Sendable {  // all state guarded by `lock`, NSP-009
    private let lock = NSLock()
    private var nanoseconds: UInt64

    public init(startingAtNanoseconds nanoseconds: UInt64 = 0) {
        self.nanoseconds = nanoseconds
    }

    public func nowNanoseconds() -> UInt64 {
        lock.withLock { nanoseconds }
    }

    public func advance(byNanoseconds delta: UInt64) {
        lock.withLock { nanoseconds += delta }
    }
}
