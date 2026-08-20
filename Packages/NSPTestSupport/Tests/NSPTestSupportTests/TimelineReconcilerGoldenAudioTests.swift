import Foundation
import NSPCore
import NSPMedia
import Testing

@testable import NSPTestSupport

/// TC-CAP-006 (docs/03 §13, NSP-025): "golden-tone drift < 250 ms at 60
/// min." Lives here rather than `NSPMediaTests` because it needs
/// `GoldenToneBurstGenerator`, which depends on `NSPMedia` — the same
/// reasoning as NSP-014's kill-injection test.
@Suite("TimelineReconciler — golden-tone drift (TC-CAP-006)")
struct TimelineReconcilerGoldenAudioTests {
    @Test func test_deviceOffset_withOverlappingGoldenAudio_refinesWithinTheDriftBudget() {
        let sampleRate = 16000
        let (originAudio, _) = GoldenToneBurstGenerator.generate(
            sampleRate: sampleRate, burstCount: 3, burstDuration: 0.15, gapDuration: 0.2)

        // Simulate device B starting exactly 311 samples "late" relative to
        // device A — device B's stream is device A's, shifted forward.
        let trueOffsetSamples = 311
        let deviceAudio = Array(originAudio.dropFirst(trueOffsetSamples))

        let origin = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()), sampleZeroWallClock: Date(timeIntervalSince1970: 0),
            sampleRate: sampleRate)
        // A deliberately imprecise wall-clock anchor (off by ~600 samples)
        // — correlation must recover the true offset despite it, as long as
        // it's within the search radius.
        let noisyWallClockOffsetSamples = 600.0
        let other = DeviceAnchor(
            deviceID: DeviceID(rawValue: UUID()),
            sampleZeroWallClock: Date(timeIntervalSince1970: noisyWallClockOffsetSamples / Double(sampleRate)),
            sampleRate: sampleRate)

        let offset = TimelineReconciler.deviceOffset(
            for: other, relativeToOrigin: origin, originAudio: originAudio, deviceAudio: deviceAudio,
            correlationWindowSamples: originAudio.count, searchRadiusSamples: 800, confidenceFloor: 0.9)

        #expect(offset.anchorEstimated == false)
        let driftSamples = abs(offset.canonicalSampleOffset - Int64(trueOffsetSamples))
        let driftBudgetSamples = Int64(0.25 * Double(sampleRate))  // < 250 ms
        #expect(driftSamples < driftBudgetSamples)
    }
}
