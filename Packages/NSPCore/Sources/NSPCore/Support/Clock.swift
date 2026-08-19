import Foundation

/// Wall-clock time source. Used for display and cross-device anchoring, and
/// for minting time-ordered IDs — never for timeline duration math
/// (docs/11 §4, "No Date() in domain logic").
public protocol Clock: Sendable {
    func now() -> Date
}

/// The real system clock. Composition roots wire this in; tests inject a
/// deterministic fake from NSPTestSupport instead.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Monotonically increasing device-local duration, for elapsed-time math
/// (retry backoff, timeouts) that must never be perturbed by wall-clock
/// changes. Recording timelines use sample counts, not this protocol
/// (docs/03, "Timeline math").
public protocol MonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

/// The real monotonic clock, backed by `ProcessInfo.systemUptime` so this
/// module stays Foundation-only (docs/01 §3).
public struct SystemMonotonicClock: MonotonicClock {
    public init() {}
    public func nowNanoseconds() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }
}
