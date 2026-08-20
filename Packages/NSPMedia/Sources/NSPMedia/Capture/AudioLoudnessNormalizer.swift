import Foundation

/// A single-band automatic gain control: brings quiet/distant speech up and
/// loud/close speech down toward one target loudness, so a recording
/// doesn't depend on everyone being the same distance from the phone.
/// Runs on the audio render thread inside `AVAudioEngineCaptureBackend`'s
/// tap — same rules as `AudioLevelMeter`'s own doc comment (no allocation,
/// no logging, no actor hop) — but needs no lock: unlike `AudioLevelMeter`
/// (written on the audio thread, read from the UI thread), this is only
/// ever touched by the single tap closure that owns it.
///
/// Per call: below the noise gate, hold the current gain rather than
/// chasing silence or room noise toward the target. Otherwise derive a
/// desired gain from this block's RMS and slew `currentGain` toward it —
/// fast (`attackSeconds`) when reducing, to avoid clipping a sudden loud
/// moment; slow (`releaseSeconds`) when raising, to avoid audibly "pumping"
/// during a brief pause. The final `[-1, 1]` clamp is a hard safety net
/// independent of how well-tuned the slew above it is — no output sample
/// can ever leave valid range, whatever the gain math decided.
///
/// Defaults are principled starting points, not a tuned-and-final result —
/// see the plan this shipped with: real tuning needs physical-hardware
/// listening tests (docs/03 §7's hardware validation gate), which no
/// Simulator run can substitute for.
public final class AudioLoudnessNormalizer: @unchecked Sendable {
    private let sampleRate: Double
    private let targetLinear: Float
    private let noiseGateLinear: Float
    private let maxGainLinear: Float
    private let minGainLinear: Float
    private let attackSeconds: Float
    private let releaseSeconds: Float

    private var currentGain: Float = 1.0

    public init(
        sampleRate: Double,
        targetDecibels: Float = -20,
        noiseGateDecibels: Float = -50,
        maxGainDecibels: Float = 30,
        minGainDecibels: Float = -12,
        attackSeconds: Float = 0.05,
        releaseSeconds: Float = 0.6
    ) {
        self.sampleRate = sampleRate
        self.targetLinear = Self.linear(fromDecibels: targetDecibels)
        self.noiseGateLinear = Self.linear(fromDecibels: noiseGateDecibels)
        self.maxGainLinear = Self.linear(fromDecibels: maxGainDecibels)
        self.minGainLinear = Self.linear(fromDecibels: minGainDecibels)
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }

    public func process(_ samples: UnsafeMutableBufferPointer<Float>) {
        guard !samples.isEmpty else { return }

        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()

        if rms >= noiseGateLinear {
            let desiredGain = min(max(targetLinear / max(rms, 1e-9), minGainLinear), maxGainLinear)
            let blockDuration = Float(samples.count) / Float(sampleRate)
            let timeConstant = desiredGain < currentGain ? attackSeconds : releaseSeconds
            let coefficient = 1 - exp(-blockDuration / timeConstant)
            currentGain += (desiredGain - currentGain) * coefficient
        }

        for index in samples.indices {
            samples[index] = min(max(samples[index] * currentGain, -1), 1)
        }
    }

    private static func linear(fromDecibels decibels: Float) -> Float {
        pow(10, decibels / 20)
    }
}
