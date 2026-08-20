import Foundation

/// A best-effort, display-only input level — the "is my mic actually
/// picking anything up" assurance docs/07 §4 calls a "waveform-free level
/// meter." `record(samples:)` runs on the real-time audio thread (the same
/// rules as `CaptureBackend.startEngine`'s tap block: no allocation, no
/// logging, no actor hop), so this is a lock-protected scalar rather than
/// anything actor-isolated — the same tradeoff `AudioRingBuffer` documents
/// for the same reason. Never read by anything durability-related; a
/// dropped or stale level reading affects only what a human sees on
/// screen, never what gets written to disk.
public final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var level: Float = 0

    public init() {}

    /// Computes an RMS-to-decibel level from `samples` and stores it,
    /// normalized to 0...1 (`-50 dB` floor, `0 dB` ceiling — enough
    /// headroom that ordinary speech moves the meter without pinning it).
    public func record(samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-9))
        let normalized = min(max((decibels + 50) / 50, 0), 1)
        lock.lock()
        level = normalized
        lock.unlock()
    }

    /// The most recent level, or `0` before the first buffer arrives.
    /// Safe to call from any thread/actor — that's the entire point of
    /// this type.
    public func currentLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return level
    }
}
