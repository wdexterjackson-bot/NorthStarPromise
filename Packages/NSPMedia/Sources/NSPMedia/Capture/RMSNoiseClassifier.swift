import Foundation

/// The RMS-in-dB noise/speech rule `AudioDynamicsProcessor` (tier 2) has
/// always used, pulled out so `SpectralNoiseSuppressor` (tier 3) can share
/// it as its own noise-vs-speech classifier. Tier 3 needs its own copy of
/// this decision because it now runs *before* tier 2 in the capture chain
/// (`AVAudioEngineCaptureBackend`'s doc comment explains the ordering) and
/// so can't reach into tier 2's per-block runtime state. Stateless and
/// allocation-free — safe to call from the audio render thread.
enum RMSNoiseClassifier {
    static func rmsDecibels(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return 20 * log10(max(rms, 1e-9))
    }

    static func isLikelyNoise(rmsDecibels: Float, expanderThresholdDecibels: Float) -> Bool {
        rmsDecibels < expanderThresholdDecibels
    }
}
