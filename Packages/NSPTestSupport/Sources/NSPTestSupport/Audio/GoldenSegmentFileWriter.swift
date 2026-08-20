import Foundation
import NSPMedia

/// Pairs `GoldenToneBurstGenerator`'s deterministic PCM with a real
/// `AVAudioFileSegmentEncoder` to produce genuine, tiny on-disk `.m4a`
/// segment files — for tests that need actual encoded audio (concatenation,
/// duration checks), not just the in-memory `[Float]` samples the generator
/// alone provides.
public enum GoldenSegmentFileWriter {
    /// Writes one real AAC `.m4a` file at `url` containing `burstCount` tone
    /// bursts at `format`. Returns the same ground truth
    /// `GoldenToneBurstGenerator.generate` would, for callers that need to
    /// assert against known content or sample count.
    @discardableResult
    public static func write(
        to url: URL, format: SegmentAudioFormat, burstCount: Int, burstDuration: TimeInterval = 0.2,
        gapDuration: TimeInterval = 0.5, frequencyHz: Double = 440
    ) throws -> (sampleCount: Int, bursts: [ToneBurst]) {
        let (samples, bursts) = GoldenToneBurstGenerator.generate(
            sampleRate: format.sampleRate, burstCount: burstCount, burstDuration: burstDuration,
            gapDuration: gapDuration, frequencyHz: frequencyHz)

        let encoder = AVAudioFileSegmentEncoder()
        try encoder.startSegment(at: url, format: format)
        try encoder.append(samples)
        try encoder.finishWriting()

        return (samples.count, bursts)
    }
}
