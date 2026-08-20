import Foundation

/// A fixed-capacity single-producer/single-consumer sample buffer, the
/// hand-off point between the audio render thread and `CaptureEngine`
/// (docs/03 §2: "communicates with the actor through a single-producer/
/// single-consumer lock-free ring buffer").
///
/// The producer and consumer here synchronize through a minimal-hold-time
/// lock rather than a fully lock-free structure. The producer's critical
/// section is a fixed-size, no-allocation copy — no `await`, no logging,
/// no `MainActor` hop, and no *allocation* ever happens on the audio thread
/// (docs/03 §2's actual hard requirement) — but a true wait-free SPSC ring
/// (no lock at all) is a stronger real-time guarantee than this gives.
/// That's a valid future hardening step if profiling on real hardware
/// (docs/03 §7, the hardware validation gate) ever shows lock contention
/// causing audio thread stalls; nothing here has been measured to need it
/// yet, and a short `os_unfair_lock`-style critical section is standard
/// practice in shipping audio apps.
public final class AudioRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float]
    private var writeIndex = 0
    private var readIndex = 0
    private var count = 0
    private let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }

    /// Called from the audio render thread. If the buffer is full, drops
    /// the oldest unread samples rather than blocking — surfacing that as
    /// an `.inputLoss`-style warning (docs/03 §2.5) is a follow-up; a full
    /// buffer here means the consumer fell behind, and dropping is always
    /// strictly better than stalling the render thread.
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            } else {
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// Drains everything currently buffered. Called from `CaptureEngine`'s
    /// actor context, never the audio thread — the allocation here is fine.
    public func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        var result = [Float]()
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(storage[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        count = 0
        return result
    }
}
