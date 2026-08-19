import Foundation

/// One known tone burst inside a generated golden clip, with the exact
/// sample range it occupies — the ground truth a test checks a segmenter,
/// timeline reconciler, or ASR word-timing result against (docs/01 §3,
/// "NSPTestSupport... generated golden audio with known tones").
public struct ToneBurst: Sendable, Hashable {
    public let range: SampleRangeSpec
    public let frequencyHz: Double
}

/// A plain start/end sample pair, independent of `NSPCore.SampleRange` so
/// this module has no dependency direction surprises — audio generation is
/// useful even to a test that never touches `NSPCore` domain types.
public struct SampleRangeSpec: Sendable, Hashable {
    public let startSample: Int64
    public let endSample: Int64
}

/// Generates deterministic PCM: silence, then alternating tone bursts and
/// silence gaps, at a known sample rate. No randomness — the same
/// parameters always produce byte-identical output, so a golden-audio drift
/// test (`TC-CAP-006`) has a stable baseline.
public enum GoldenToneBurstGenerator {
    /// - Parameters:
    ///   - sampleRate: samples per second.
    ///   - burstCount: number of tone bursts to emit.
    ///   - burstDuration: length of each tone burst, in seconds.
    ///   - gapDuration: length of silence before each burst (including the
    ///     leading silence before the first one).
    ///   - frequencyHz: sine frequency for every burst.
    /// - Returns: mono `Float` samples in `[-1, 1]`, and the exact sample
    ///   range of each burst within that array.
    public static func generate(
        sampleRate: Int,
        burstCount: Int,
        burstDuration: TimeInterval = 0.2,
        gapDuration: TimeInterval = 0.5,
        frequencyHz: Double = 440
    ) -> (samples: [Float], bursts: [ToneBurst]) {
        precondition(sampleRate > 0 && burstCount >= 0)

        let gapSamples = Int(gapDuration * Double(sampleRate))
        let burstSamples = Int(burstDuration * Double(sampleRate))

        var samples: [Float] = []
        var bursts: [ToneBurst] = []
        samples.reserveCapacity((gapSamples + burstSamples) * max(burstCount, 1))

        for _ in 0..<burstCount {
            samples.append(contentsOf: repeatElement(0, count: gapSamples))

            let start = Int64(samples.count)
            for sampleIndex in 0..<burstSamples {
                let t = Double(sampleIndex) / Double(sampleRate)
                samples.append(Float(sin(2 * Double.pi * frequencyHz * t)))
            }
            let end = Int64(samples.count)

            let range = SampleRangeSpec(startSample: start, endSample: end)
            bursts.append(ToneBurst(range: range, frequencyHz: frequencyHz))
        }

        return (samples, bursts)
    }
}
