import Foundation
import Testing

@testable import NSPMedia

@Suite("AudioLoudnessNormalizer")
struct AudioLoudnessNormalizerTests {
    private static let sampleRate = 48000.0
    private static let blockSize = 1024

    /// A steady sine tone at `decibels` RMS, split into `blockCount` blocks
    /// of `blockSize` samples each, matching the real tap's call shape.
    private static func toneBlocks(decibels: Float, blockCount: Int, frequencyHz: Double = 440) -> [[Float]] {
        let amplitude = pow(10, decibels / 20) * Float(2).squareRoot()  // RMS -> peak for a sine
        var blocks: [[Float]] = []
        var sampleIndex = 0
        for _ in 0..<blockCount {
            var block: [Float] = []
            block.reserveCapacity(blockSize)
            for _ in 0..<blockSize {
                let t = Double(sampleIndex) / sampleRate
                block.append(amplitude * Float(sin(2 * Double.pi * frequencyHz * t)))
                sampleIndex += 1
            }
            blocks.append(block)
        }
        return blocks
    }

    private static func rmsDecibels(_ samples: [Float]) -> Float {
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return 20 * log10(max(rms, 1e-9))
    }

    private static func process(_ normalizer: AudioLoudnessNormalizer, _ block: [Float]) -> [Float] {
        var mutableBlock = block
        mutableBlock.withUnsafeMutableBufferPointer { normalizer.process($0) }
        return mutableBlock
    }

    @Test func test_process_quietSteadyTone_convergesTowardTargetLevel() {
        let normalizer = AudioLoudnessNormalizer(sampleRate: Self.sampleRate)
        let blocks = Self.toneBlocks(decibels: -40, blockCount: 60)

        var lastOutput: [Float] = []
        for block in blocks {
            lastOutput = Self.process(normalizer, block)
        }

        // Default target is -20dB; allow a few dB tolerance for the sine
        // RMS-vs-peak relationship and the discrete per-block slew.
        #expect(abs(Self.rmsDecibels(lastOutput) - (-20)) < 3)
    }

    @Test func test_process_loudTone_isReducedTowardTargetAndNeverClips() {
        let normalizer = AudioLoudnessNormalizer(sampleRate: Self.sampleRate)
        let blocks = Self.toneBlocks(decibels: -3, blockCount: 60)

        var lastOutput: [Float] = []
        for block in blocks {
            lastOutput = Self.process(normalizer, block)
            for sample in lastOutput {
                #expect(sample >= -1 && sample <= 1)
            }
        }

        #expect(Self.rmsDecibels(lastOutput) < -3)
    }

    @Test func test_process_silenceBelowNoiseGate_isNotSignificantlyAmplified() {
        let normalizer = AudioLoudnessNormalizer(sampleRate: Self.sampleRate)
        let blocks = Self.toneBlocks(decibels: -70, blockCount: 30)

        var lastOutput: [Float] = []
        for block in blocks {
            lastOutput = Self.process(normalizer, block)
        }

        // Gain should have stayed near unity (0dB) rather than chasing the
        // target — output level should still be close to the input's -70dB,
        // not boosted toward -20dB.
        #expect(Self.rmsDecibels(lastOutput) < -50)
    }

    @Test func test_process_suddenLoudBurstAfterQuiet_neverExceedsSafetyBounds() {
        let normalizer = AudioLoudnessNormalizer(sampleRate: Self.sampleRate)
        // Let gain climb toward maxGain against a quiet, steady tone first.
        for block in Self.toneBlocks(decibels: -40, blockCount: 80) {
            _ = Self.process(normalizer, block)
        }

        // Now an abrupt full-scale block — the safety clamp, not the slew
        // (which can't react within one block), must hold the line.
        let loudBlock = Self.toneBlocks(decibels: 0, blockCount: 1).first!
        let output = Self.process(normalizer, loudBlock)

        for sample in output {
            #expect(sample >= -1 && sample <= 1)
        }
    }

    @Test func test_process_gainChangesSmoothly_noAbruptJumpBetweenBlocks() {
        let normalizer = AudioLoudnessNormalizer(sampleRate: Self.sampleRate)
        let blocks = Self.toneBlocks(decibels: -40, blockCount: 40)

        var previousRatio: Float?
        for block in blocks {
            let output = Self.process(normalizer, block)
            // The effective gain this block applied, inferred from the
            // ratio of output to input peak amplitude.
            let inputPeak = block.map { abs($0) }.max() ?? 0
            let outputPeak = output.map { abs($0) }.max() ?? 0
            guard inputPeak > 0 else { continue }
            let ratio = outputPeak / inputPeak
            if let previousRatio {
                // Attack/release coefficients bound how far gain can move
                // in one ~21ms block; a jump anywhere near the full
                // min-to-max gain range in a single block would mean the
                // slew isn't being applied at all.
                #expect(abs(ratio - previousRatio) < 10)
            }
            previousRatio = ratio
        }
    }
}
