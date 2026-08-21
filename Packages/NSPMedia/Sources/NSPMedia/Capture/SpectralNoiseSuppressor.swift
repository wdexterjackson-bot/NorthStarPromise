import Accelerate
import Foundation

/// Tier 3 of the background-noise-cleanup work (docs/03 §2.6): FFT-based
/// spectral subtraction (Wiener-style spectral gating with a floor) for
/// noise happening *simultaneously* with speech — the case tier 2's
/// RMS-based expander can't separate, since it only ever sees one number
/// per block. Runs on the audio render thread inside
/// `AVAudioEngineCaptureBackend`'s tap, ahead of tier 2 — same rules as
/// `AudioDynamicsProcessor`'s own doc comment (no allocation, no logging,
/// no actor hop after `init`) — but unlike tier 2, `process(_:)` does not
/// mutate in place: STFT/overlap-add reconstruction is inherently
/// block-buffered (a hop of algorithmic latency, up to ~20-30 ms), so the
/// output for a given call's input generally isn't ready until a later
/// call. Every buffer this type ever touches is allocated exactly once, in
/// `init`, and freed in `deinit` — nothing here is safe to construct on the
/// audio thread itself, which is why `AVAudioEngineCaptureBackend` builds
/// it at `startEngine` time, before the tap is installed.
///
/// Uses a full complex-to-complex FFT (`vDSP_fft_zip`) rather than vDSP's
/// real-optimized packed FFT (`vDSP_fft_zrip`) — real input still doubles
/// the practical bin/compute cost, but sidesteps that API's fiddly
/// DC/Nyquist packing convention entirely. That convention is a well-known
/// source of subtle, hard-to-notice correctness bugs, and getting the
/// *sign* of noise suppression wrong is a much worse failure than the 2×
/// compute overhead — especially for a tier that already ships behind a
/// default-off feature flag pending real hardware measurement.
///
/// Defaults are principled starting points, not a tuned-and-final result —
/// same caveat `AudioDynamicsProcessor`'s doc comment makes for its own
/// constants; real tuning needs the physical-hardware listening tests
/// `docs/03` §7's hardware validation gate calls for.
public final class SpectralNoiseSuppressor: @unchecked Sendable {
    private let frameSize: Int
    private let hopSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private let expanderThresholdDecibels: Float
    private let oversubtractionFactor: Float
    private let spectralFloor: Float
    private let noiseEMACoefficient: Float

    private let window: UnsafeMutableBufferPointer<Float>
    /// Reciprocal of the steady-state two-frame Hann overlap-sum, one entry
    /// per output sample within a hop — computed once, numerically, in
    /// `init` (`computeCOLAReciprocal`), rather than trusted from a
    /// textbook constant that depends on this exact window's normalization
    /// convention. Applied only to the finalized (fully-overlapped) region
    /// of a hop; the very first hop of a stream and the tail drained by
    /// `flush()` are each the product of only one contributing frame, not
    /// two, so this correction is intentionally *not* applied there (see
    /// `process`/`flush`) — a small, bounded, honestly-undocumented-as-such
    /// loudness dip on the first and last ~20 ms of every Tier-3 recording,
    /// not a bug.
    private let colaReciprocal: UnsafeMutableBufferPointer<Float>

    private let realBuffer: UnsafeMutableBufferPointer<Float>
    private let imagBuffer: UnsafeMutableBufferPointer<Float>
    private let magnitudeSquared: UnsafeMutableBufferPointer<Float>
    private let gain: UnsafeMutableBufferPointer<Float>
    private let noisePowerEstimate: UnsafeMutableBufferPointer<Float>

    /// The current analysis frame — raw (unwindowed) samples, slid left by
    /// `hopSize` and refilled from `inputFIFO` each time a full hop of new
    /// input is available.
    private let analysisFrame: UnsafeMutableBufferPointer<Float>
    private let olaAccumulator: UnsafeMutableBufferPointer<Float>

    /// Absorbs whatever size `process(_:)`'s caller hands in — the tap's
    /// `bufferSize` is only a suggestion (`AVAudioEngineCaptureBackend`'s
    /// own doc comment) — until a full `hopSize` chunk is available to feed
    /// into `analysisFrame`. Sized generously above any realistic tap
    /// `frameLength`; overflow is defensively dropped, never a crash.
    private let inputFIFO: UnsafeMutableBufferPointer<Float>
    private var inputFIFOCount = 0
    private let outputScratch: UnsafeMutableBufferPointer<Float>

    public init(
        sampleRate: Double,
        expanderThresholdDecibels: Float = -35,
        oversubtractionFactor: Float = 1.5,
        spectralFloor: Float = 0.1,
        noiseEMACoefficient: Float = 0.95
    ) {
        var frameSampleCount = 256
        let target = sampleRate * 0.02
        while frameSampleCount < Int(target), frameSampleCount < 2048 { frameSampleCount *= 2 }
        let hop = frameSampleCount / 2

        self.frameSize = frameSampleCount
        self.hopSize = hop
        self.log2n = vDSP_Length(log2(Double(frameSampleCount)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.expanderThresholdDecibels = expanderThresholdDecibels
        self.oversubtractionFactor = oversubtractionFactor
        self.spectralFloor = spectralFloor
        self.noiseEMACoefficient = noiseEMACoefficient

        let window = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameSampleCount)
        vDSP_hann_window(window.baseAddress!, vDSP_Length(frameSampleCount), Int32(vDSP_HANN_DENORM))
        self.window = window

        let colaReciprocal = UnsafeMutableBufferPointer<Float>.allocate(capacity: hop)
        Self.computeCOLAReciprocal(window: window, frameSize: frameSampleCount, hopSize: hop, into: colaReciprocal)
        self.colaReciprocal = colaReciprocal

        self.realBuffer = .allocate(capacity: frameSampleCount)
        self.imagBuffer = .allocate(capacity: frameSampleCount)
        self.magnitudeSquared = .allocate(capacity: frameSampleCount)
        self.gain = .allocate(capacity: frameSampleCount)

        self.noisePowerEstimate = .allocate(capacity: frameSampleCount)
        noisePowerEstimate.initialize(repeating: 0)
        self.analysisFrame = .allocate(capacity: frameSampleCount)
        analysisFrame.initialize(repeating: 0)
        self.olaAccumulator = .allocate(capacity: frameSampleCount)
        olaAccumulator.initialize(repeating: 0)

        let fifoCapacity = max(frameSampleCount * 4, 8192)
        self.inputFIFO = .allocate(capacity: fifoCapacity)
        let scratchCapacity = max(frameSampleCount * 4, 8192)
        self.outputScratch = .allocate(capacity: scratchCapacity)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        window.deallocate()
        colaReciprocal.deallocate()
        realBuffer.deallocate()
        imagBuffer.deallocate()
        magnitudeSquared.deallocate()
        gain.deallocate()
        noisePowerEstimate.deallocate()
        analysisFrame.deallocate()
        olaAccumulator.deallocate()
        inputFIFO.deallocate()
        outputScratch.deallocate()
    }

    /// Returns a view into `outputScratch` valid until the next call to
    /// `process`/`flush` — 0, 1, or several completed hops' worth, since
    /// hop completion isn't 1:1 with how many samples a given tap call
    /// happens to deliver.
    public func process(_ input: UnsafeBufferPointer<Float>) -> UnsafeBufferPointer<Float> {
        let roomLeft = inputFIFO.count - inputFIFOCount
        let toCopy = min(input.count, roomLeft)
        if toCopy > 0 {
            for i in 0..<toCopy { inputFIFO[inputFIFOCount + i] = input[i] }
            inputFIFOCount += toCopy
        }

        var outputCount = 0
        while inputFIFOCount >= hopSize, outputCount + hopSize <= outputScratch.count {
            consumeOneHop()
            processOneFrame()
            emitFinalizedHop(into: &outputCount, applyCOLACorrection: true)
        }

        return UnsafeBufferPointer(rebasing: outputScratch[0..<outputCount])
    }

    /// Drains whatever's left at `stopEngine()` — a zero-padded final
    /// partial hop (if any real samples are still waiting in `inputFIFO`)
    /// plus the last processed frame's not-yet-combined second half, which
    /// the main loop in `process` never emits on its own since nothing
    /// after it exists to overlap-add with. Without this, the tail of
    /// every Tier-3 recording would be silently short by up to one frame.
    public func flush() -> UnsafeBufferPointer<Float> {
        var outputCount = 0

        if inputFIFOCount > 0 {
            let pad = hopSize - inputFIFOCount
            if pad > 0 {
                for i in 0..<pad { inputFIFO[inputFIFOCount + i] = 0 }
                inputFIFOCount += pad
            }
            consumeOneHop()
            processOneFrame()
            emitFinalizedHop(into: &outputCount, applyCOLACorrection: true)
        }

        // The tail: `olaAccumulator`'s upper half holds the last frame's
        // second-half contribution, which only ever gets finalized by a
        // *following* frame's overlap-add — there isn't one. Emitted raw
        // (no COLA correction; see `colaReciprocal`'s doc comment).
        let tailCount = frameSize - hopSize
        for i in 0..<tailCount {
            outputScratch[outputCount + i] = min(max(olaAccumulator[i], -1), 1)
        }
        outputCount += tailCount
        for i in 0..<frameSize { olaAccumulator[i] = 0 }

        return UnsafeBufferPointer(rebasing: outputScratch[0..<outputCount])
    }

    /// Slides `analysisFrame` left by `hopSize` and refills its tail from
    /// the front of `inputFIFO`, then compacts `inputFIFO` by the same
    /// amount. Leaves exactly one hop's worth of new signal absorbed into
    /// the frame every call.
    private func consumeOneHop() {
        for i in 0..<(frameSize - hopSize) {
            analysisFrame[i] = analysisFrame[i + hopSize]
        }
        for i in 0..<hopSize {
            analysisFrame[frameSize - hopSize + i] = inputFIFO[i]
        }
        let remaining = inputFIFOCount - hopSize
        for i in 0..<remaining {
            inputFIFO[i] = inputFIFO[i + hopSize]
        }
        inputFIFOCount = remaining
    }

    /// Copies `olaAccumulator`'s finalized front hop into `outputScratch`
    /// (optionally COLA-corrected), then shifts the accumulator left by one
    /// hop and zeros the newly-vacated tail, ready for the next frame's
    /// overlap-add.
    private func emitFinalizedHop(into outputCount: inout Int, applyCOLACorrection: Bool) {
        // A hard safety net independent of how well-behaved the spectral
        // gain math is — same reasoning `AudioDynamicsProcessor.process`'s
        // own final clamp documents: no output sample leaves valid range,
        // whatever upstream arithmetic decided.
        if applyCOLACorrection {
            for i in 0..<hopSize {
                outputScratch[outputCount + i] = min(max(olaAccumulator[i] * colaReciprocal[i], -1), 1)
            }
        } else {
            for i in 0..<hopSize {
                outputScratch[outputCount + i] = min(max(olaAccumulator[i], -1), 1)
            }
        }
        outputCount += hopSize

        for i in 0..<(frameSize - hopSize) {
            olaAccumulator[i] = olaAccumulator[i + hopSize]
        }
        for i in (frameSize - hopSize)..<frameSize {
            olaAccumulator[i] = 0
        }
    }

    /// One full STFT-domain pass over `analysisFrame`: window, forward FFT,
    /// classify and update the noise profile, apply the spectral-gain
    /// curve, inverse FFT, and overlap-add the result into
    /// `olaAccumulator`. All scratch buffers are the fixed, pre-allocated
    /// ones from `init` — no allocation on this path.
    private func processOneFrame() {
        vDSP_vmul(
            analysisFrame.baseAddress!, 1, window.baseAddress!, 1, realBuffer.baseAddress!, 1, vDSP_Length(frameSize))
        for i in 0..<frameSize { imagBuffer[i] = 0 }

        var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
        vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, magnitudeSquared.baseAddress!, 1, vDSP_Length(frameSize))

        let rmsDecibels = RMSNoiseClassifier.rmsDecibels(UnsafeBufferPointer(analysisFrame))
        let isNoise = RMSNoiseClassifier.isLikelyNoise(
            rmsDecibels: rmsDecibels, expanderThresholdDecibels: expanderThresholdDecibels)
        if isNoise {
            for i in 0..<frameSize {
                noisePowerEstimate[i] =
                    noiseEMACoefficient * noisePowerEstimate[i] + (1 - noiseEMACoefficient) * magnitudeSquared[i]
            }
        }

        // G[k] = clamp(1 - β·N[k]/max(|X[k]|², ε), floor, 1) — a real input
        // signal's spectrum is conjugate-symmetric (|X[N-k]| == |X[k]|), and
        // this gain is a pure function of each bin's own magnitude and its
        // own noise estimate, so the resulting gain curve is automatically
        // symmetric too, and the inverse FFT stays real without any
        // separate DC/Nyquist handling.
        let epsilon: Float = 1e-12
        for i in 0..<frameSize {
            let denom = max(magnitudeSquared[i], epsilon)
            let raw = 1 - oversubtractionFactor * (noisePowerEstimate[i] / denom)
            gain[i] = min(max(raw, spectralFloor), 1)
        }

        vDSP_vmul(realBuffer.baseAddress!, 1, gain.baseAddress!, 1, realBuffer.baseAddress!, 1, vDSP_Length(frameSize))
        vDSP_vmul(imagBuffer.baseAddress!, 1, gain.baseAddress!, 1, imagBuffer.baseAddress!, 1, vDSP_Length(frameSize))

        vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
        var scale = Float(1.0 / Double(frameSize))
        vDSP_vsmul(realBuffer.baseAddress!, 1, &scale, realBuffer.baseAddress!, 1, vDSP_Length(frameSize))

        vDSP_vadd(
            olaAccumulator.baseAddress!, 1, realBuffer.baseAddress!, 1, olaAccumulator.baseAddress!, 1,
            vDSP_Length(frameSize))
    }

    /// Numerically simulates enough overlapping Hann frames at `hopSize`
    /// spacing to reach a steady state, then reads back one hop's worth of
    /// the resulting overlap-sum from the middle (away from start/end
    /// transients) and stores its reciprocal. Deliberately not a trusted
    /// textbook constant — `vDSP_hann_window`'s exact normalization isn't
    /// worth assuming blind, and this is `init`-time work, off the audio
    /// thread, so the cost of computing it properly is free.
    private static func computeCOLAReciprocal(
        window: UnsafeMutableBufferPointer<Float>, frameSize: Int, hopSize: Int,
        into result: UnsafeMutableBufferPointer<Float>
    ) {
        let simulationLength = frameSize * 6
        var overlapSum = [Float](repeating: 0, count: simulationLength)
        var frameStart = 0
        while frameStart + frameSize <= simulationLength {
            for i in 0..<frameSize {
                overlapSum[frameStart + i] += window[i]
            }
            frameStart += hopSize
        }
        let steadyStateStart = simulationLength / 2
        for i in 0..<hopSize {
            let sum = overlapSum[steadyStateStart + i]
            result[i] = sum > 1e-6 ? 1 / sum : 1
        }
    }
}
