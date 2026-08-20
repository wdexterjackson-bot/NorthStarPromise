import Foundation

/// A single-band dynamics processor: brings quiet/distant speech up and
/// loud/close speech down toward one target loudness (automatic gain
/// control), and actively suppresses background noise in the gap between
/// true silence and speech (a downward expander) instead of accidentally
/// boosting it toward the target the way plain AGC alone would. Runs on
/// the audio render thread inside `AVAudioEngineCaptureBackend`'s tap —
/// same rules as `AudioLevelMeter`'s own doc comment (no allocation, no
/// logging, no actor hop) — but needs no lock: unlike `AudioLevelMeter`
/// (written on the audio thread, read from the UI thread), this is only
/// ever touched by the single tap closure that owns it.
///
/// Per call, three zones by this block's RMS:
///   - below `noiseGateDecibels`: hold the current gain — true silence,
///     nothing to expand or normalize.
///   - between the noise gate and `expanderThresholdDecibels`: probably
///     background noise, not speech. Plain AGC would boost this zone
///     toward the target since it's quieter than target — backwards for
///     noise — so instead it's pushed down: `expansionRatio` controls how
///     much extra attenuation is applied per dB below the threshold.
///   - at or above `expanderThresholdDecibels`: probably speech — normal
///     AGC (boost toward target, or cut if too loud).
/// Whichever zone, the resulting desired gain is slewed toward smoothly —
/// fast (`attackSeconds`) when reducing, to avoid clipping a sudden loud
/// moment; slow (`releaseSeconds`) when raising, to avoid audibly "pumping"
/// during a brief pause. The final `[-1, 1]` clamp is a hard safety net
/// independent of how well-tuned the slew above it is — no output sample
/// can ever leave valid range, whatever the gain math decided.
///
/// Defaults are principled starting points, not a tuned-and-final result —
/// real tuning needs physical-hardware listening tests (docs/03 §7's
/// hardware validation gate), which no Simulator run can substitute for.
public final class AudioDynamicsProcessor: @unchecked Sendable {
    private let sampleRate: Double
    private let targetLinear: Float
    private let noiseGateLinear: Float
    private let maxGainLinear: Float
    private let minGainLinear: Float
    private let attackSeconds: Float
    private let releaseSeconds: Float
    private let expanderThresholdDecibels: Float
    private let expansionRatio: Float

    private var currentGain: Float = 1.0

    public init(
        sampleRate: Double,
        targetDecibels: Float = -20,
        noiseGateDecibels: Float = -50,
        maxGainDecibels: Float = 30,
        minGainDecibels: Float = -12,
        attackSeconds: Float = 0.05,
        releaseSeconds: Float = 0.6,
        expanderThresholdDecibels: Float = -35,
        expansionRatio: Float = 3
    ) {
        self.sampleRate = sampleRate
        self.targetLinear = Self.linear(fromDecibels: targetDecibels)
        self.noiseGateLinear = Self.linear(fromDecibels: noiseGateDecibels)
        self.maxGainLinear = Self.linear(fromDecibels: maxGainDecibels)
        self.minGainLinear = Self.linear(fromDecibels: minGainDecibels)
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.expanderThresholdDecibels = expanderThresholdDecibels
        self.expansionRatio = expansionRatio
    }

    public func process(_ samples: UnsafeMutableBufferPointer<Float>) {
        guard !samples.isEmpty else { return }

        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()

        if rms >= noiseGateLinear {
            let desiredGain = desiredGain(forRMS: rms)
            let blockDuration = Float(samples.count) / Float(sampleRate)
            let timeConstant = desiredGain < currentGain ? attackSeconds : releaseSeconds
            let coefficient = 1 - exp(-blockDuration / timeConstant)
            currentGain += (desiredGain - currentGain) * coefficient
        }

        for index in samples.indices {
            samples[index] = min(max(samples[index] * currentGain, -1), 1)
        }
    }

    /// Below `expanderThresholdDecibels`: a standard downward-expander
    /// transfer curve — `outputDb = threshold + (inputDb - threshold) *
    /// ratio` — so output drops `ratio` times faster than input as the
    /// signal gets quieter (active suppression, anchored continuously at
    /// unity right at the threshold). At/above the threshold: plain AGC
    /// (boost toward `targetLinear`, or cut if too loud). These are two
    /// genuinely different curves, not one curve with a penalty subtracted
    /// — a boost-minus-penalty formulation was tried and rejected because
    /// it can still net out as a boost when the AGC's desired boost is
    /// large, which is exactly backwards for noise.
    private func desiredGain(forRMS rms: Float) -> Float {
        let rmsDecibels = 20 * log10(max(rms, 1e-9))
        guard rmsDecibels < expanderThresholdDecibels else {
            return min(max(targetLinear / max(rms, 1e-9), minGainLinear), maxGainLinear)
        }

        let outputDecibels = expanderThresholdDecibels + (rmsDecibels - expanderThresholdDecibels) * expansionRatio
        let expandedGain = Self.linear(fromDecibels: outputDecibels - rmsDecibels)
        return min(max(expandedGain, minGainLinear), maxGainLinear)
    }

    private static func linear(fromDecibels decibels: Float) -> Float {
        pow(10, decibels / 20)
    }
}
