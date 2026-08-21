import Foundation
import Testing

@testable import NSPMedia

@Suite("SpectralNoiseSuppressor")
struct SpectralNoiseSuppressorTests {
    private static let sampleRate = 48000.0
    /// Matches the real tap's suggested `bufferSize` — feeding chunks this
    /// size (rather than the whole signal in one call) exercises the same
    /// FIFO/hop-accumulation path the real capture backend drives.
    private static let tapChunkSize = 1024

    // MARK: - Local, deterministic signal generators (no Foundation
    // randomness — same precedent `AudioDynamicsProcessorTests` sets: a
    // small local synthesizer per file rather than a shared golden
    // generator, since `NSPTestSupport`'s only makes clean tone bursts with
    // no noise signal).

    private struct SeededGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
        mutating func nextUnitFloat() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let normalized = Double(state >> 11) / Double(1 << 53)
            return Float(normalized * 2 - 1)
        }
    }

    private static func whiteNoise(decibels: Float, sampleCount: Int, seed: UInt64) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        let targetRMS = pow(10, decibels / 20)
        let uniformRMS: Float = 1 / Float(3).squareRoot()  // RMS of uniform noise in [-1, 1]
        let scale = targetRMS / uniformRMS
        return (0..<sampleCount).map { _ in generator.nextUnitFloat() * scale }
    }

    private static func tone(decibels: Float, sampleCount: Int, frequencyHz: Double) -> [Float] {
        let amplitude = pow(10, decibels / 20) * Float(2).squareRoot()  // RMS -> peak for a sine
        return (0..<sampleCount).map { index in
            let t = Double(index) / sampleRate
            return amplitude * Float(sin(2 * Double.pi * frequencyHz * t))
        }
    }

    private static func rmsDecibels(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return 20 * log10(max(rms, 1e-9))
    }

    /// Single-bin Goertzel magnitude — enough to check whether a known
    /// tone survived processing, without needing the production FFT setup.
    private static func goertzelMagnitude(_ samples: [Float], frequencyHz: Double) -> Float {
        let sampleCount = samples.count
        let binIndex = Double(sampleCount) * frequencyHz / sampleRate
        let omega = 2 * Double.pi * binIndex / Double(sampleCount)
        let coefficient = 2 * cos(omega)
        var feedback0 = 0.0
        var feedback1 = 0.0
        var feedback2 = 0.0
        for sample in samples {
            feedback0 = coefficient * feedback1 - feedback2 + Double(sample)
            feedback2 = feedback1
            feedback1 = feedback0
        }
        let real = feedback1 - feedback2 * cos(omega)
        let imaginary = feedback2 * sin(omega)
        return Float((real * real + imaginary * imaginary).squareRoot())
    }

    /// Feeds `signal` through `suppressor` in tap-sized chunks, appending
    /// every completed hop to `output` — the same call shape
    /// `AVAudioEngineCaptureBackend`'s tap drives it with.
    private static func feed(
        _ signal: [Float], through suppressor: SpectralNoiseSuppressor, into output: inout [Float]
    ) {
        signal.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let chunkSize = min(tapChunkSize, buffer.count - offset)
                let chunk = UnsafeBufferPointer(rebasing: buffer[offset..<(offset + chunkSize)])
                output.append(contentsOf: suppressor.process(chunk))
                offset += chunkSize
            }
        }
    }

    @Test func test_process_pureNoise_reducesOutputRMS() {
        let suppressor = SpectralNoiseSuppressor(sampleRate: Self.sampleRate)
        let inputDecibels: Float = -40
        // Generously long enough for the noise EMA (default coefficient
        // 0.95, ~20-hop time constant) to converge well past its 99% point.
        let noise = Self.whiteNoise(decibels: inputDecibels, sampleCount: 512 * 300, seed: 1)

        var output: [Float] = []
        Self.feed(noise, through: suppressor, into: &output)
        output.append(contentsOf: suppressor.flush())

        let steadyState = Array(output.suffix(output.count / 2))
        #expect(Self.rmsDecibels(steadyState) < inputDecibels - 6)
    }

    @Test func test_process_toneFundamental_survivesMixedWithNoise() {
        let suppressor = SpectralNoiseSuppressor(sampleRate: Self.sampleRate)

        // Converge the noise profile on noise-only frames first.
        let warmupNoise = Self.whiteNoise(decibels: -40, sampleCount: 512 * 300, seed: 2)
        var discarded: [Float] = []
        Self.feed(warmupNoise, through: suppressor, into: &discarded)

        // Noise + a tone comfortably above the expander threshold, so these
        // frames classify as speech and don't perturb the already-converged
        // noise profile mid-measurement.
        let sampleCount = 512 * 40
        let toneSignal = Self.tone(decibels: -20, sampleCount: sampleCount, frequencyHz: 1000)
        let noiseSignal = Self.whiteNoise(decibels: -40, sampleCount: sampleCount, seed: 3)
        let mixed = zip(toneSignal, noiseSignal).map(+)

        var output: [Float] = []
        Self.feed(mixed, through: suppressor, into: &output)
        output.append(contentsOf: suppressor.flush())

        let inputDb = 20 * log10(max(Self.goertzelMagnitude(mixed, frequencyHz: 1000), 1e-9))
        let outputDb = 20 * log10(max(Self.goertzelMagnitude(output, frequencyHz: 1000), 1e-9))
        // A tone concentrated in one bin sits far above the (spread-out)
        // per-bin noise floor even when the two are RMS-comparable overall
        // — the whole premise spectral subtraction relies on — so it should
        // survive with only modest attenuation, unlike the broadband noise
        // in the pure-noise test above.
        #expect(abs(outputDb - inputDb) < 6)
    }

    @Test func test_process_outputAlwaysInValidRange() {
        let suppressor = SpectralNoiseSuppressor(sampleRate: Self.sampleRate)
        var signal: [Float] = []
        signal += Self.whiteNoise(decibels: -40, sampleCount: 512 * 10, seed: 4)
        signal += Self.tone(decibels: -3, sampleCount: 512 * 10, frequencyHz: 500)
        signal += [Float](repeating: 0, count: 512 * 5)
        signal += Self.tone(decibels: 0, sampleCount: 512 * 5, frequencyHz: 2000)

        var output: [Float] = []
        Self.feed(signal, through: suppressor, into: &output)
        output.append(contentsOf: suppressor.flush())

        for sample in output {
            #expect(sample >= -1 && sample <= 1)
        }
    }

    @Test func test_process_isDeterministic() {
        let signal =
            Self.whiteNoise(decibels: -30, sampleCount: 512 * 20, seed: 5)
            + Self.tone(decibels: -20, sampleCount: 512 * 20, frequencyHz: 300)

        func run() -> [Float] {
            let suppressor = SpectralNoiseSuppressor(sampleRate: Self.sampleRate)
            var output: [Float] = []
            Self.feed(signal, through: suppressor, into: &output)
            output.append(contentsOf: suppressor.flush())
            return output
        }

        #expect(run() == run())
    }

    @Test func test_flush_outputLengthTracksInputWithinOneFrame() {
        let suppressor = SpectralNoiseSuppressor(sampleRate: Self.sampleRate)
        // Deliberately not an exact multiple of any hop/frame size.
        let totalSamples = 512 * 37 + 200
        let signal = Self.whiteNoise(decibels: -30, sampleCount: totalSamples, seed: 6)

        var output: [Float] = []
        Self.feed(signal, through: suppressor, into: &output)
        output.append(contentsOf: suppressor.flush())

        // STFT/overlap-add is a delay line, not a lossless 1:1 transform —
        // it inherently adds up to one frame's worth of algorithmic latency
        // (docs/03 §2.6's open-risk note), so exact equality isn't the
        // right bar. A generous, sizing-formula-independent bound is enough
        // to catch a gross accounting bug (e.g. half the audio silently
        // dropped) without coupling this test to the private frame-size
        // computation.
        #expect(abs(output.count - totalSamples) <= 4096)
    }
}
