import NSPCore

/// One non-origin device's position on the canonical timeline (docs/03 §4).
/// `anchorEstimated` is `true` when the wall-clock anchor stands
/// uncorrected — no overlapping audio was available, or the best
/// correlation found didn't clear the confidence floor.
public struct DeviceOffset: Sendable, Hashable {
    public let deviceID: DeviceID
    public let canonicalSampleOffset: Int64
    public let anchorEstimated: Bool

    public init(deviceID: DeviceID, canonicalSampleOffset: Int64, anchorEstimated: Bool) {
        self.deviceID = deviceID
        self.canonicalSampleOffset = canonicalSampleOffset
        self.anchorEstimated = anchorEstimated
    }
}

/// Sample-domain-only timeline math (docs/03 §4, NSP-025). Every input here
/// is either a sample count or a `Date` *value* handed in by a caller who
/// read the clock at capture time — this type itself never reads the
/// clock, which is what TC-CAP-013's "no wall-clock reads or timers in
/// timeline code" actually forbids: the call, not the type.
public enum TimelineReconciler {
    /// `Meeting.canonicalDuration` = Σ `Segment.sampleCount` + Σ recorded
    /// gap samples (docs/03 §4). Gap durations are never recomputed here —
    /// they're read verbatim from each resume/interruption-ended event's
    /// `payload["gapSamples"]`, which the segmenter already derived from a
    /// wall-clock delta at the moment the gap closed (docs/03 §4's one
    /// sanctioned use of wall clock, and not this type's job to repeat).
    public static func canonicalSampleCount(segments: [Segment], gapClosingEvents: [TimelineEvent]) -> Int64 {
        let segmentTotal = segments.reduce(Int64(0)) { $0 + $1.sampleCount }
        let gapTotal = gapClosingEvents.reduce(Int64(0)) { $0 + (gapSamples(from: $1) ?? 0) }
        return segmentTotal + gapTotal
    }

    private static func gapSamples(from event: TimelineEvent) -> Int64? {
        guard case .object(let fields) = event.payload, case .number(let value) = fields["gapSamples"] else {
            return nil
        }
        return Int64(value)
    }

    /// Maps `anchor`'s device-local sample 0 onto `origin`'s canonical
    /// timeline (docs/03 §4). Starts from the wall-clock anchor, then — if
    /// both devices' audio is supplied — refines it by cross-correlating
    /// the leading `correlationWindowSamples` of each within
    /// `± searchRadiusSamples` of the wall-clock estimate, keeping the
    /// refinement only if its correlation score clears `confidenceFloor`.
    ///
    /// The correlation search here is a direct O(window × radius) scan —
    /// correct at any scale, but production-scale windows (docs/03 §4's
    /// 30 s / ±3 s) call for an FFT-based implementation (`Accelerate`) for
    /// real-time performance; that's a follow-up optimization, not a
    /// correctness concern this ticket's acceptance depends on.
    public static func deviceOffset(
        for anchor: DeviceAnchor,
        relativeToOrigin origin: DeviceAnchor,
        originAudio: [Float]? = nil,
        deviceAudio: [Float]? = nil,
        correlationWindowSamples: Int = 30 * 16000,
        searchRadiusSamples: Int64 = 3 * 16000,
        confidenceFloor: Double = 0.6
    ) -> DeviceOffset {
        let wallClockDelta = anchor.sampleZeroWallClock.timeIntervalSince(origin.sampleZeroWallClock)
        let estimatedOffset = Int64((wallClockDelta * Double(origin.sampleRate)).rounded())

        guard let originAudio, let deviceAudio else {
            return DeviceOffset(
                deviceID: anchor.deviceID, canonicalSampleOffset: estimatedOffset, anchorEstimated: true)
        }

        let reference = Array(originAudio.prefix(correlationWindowSamples))
        let candidate = Array(deviceAudio.prefix(correlationWindowSamples))

        let refinedOffset = refineOffset(
            reference: reference, candidate: candidate, estimatedOffset: estimatedOffset,
            searchRadius: searchRadiusSamples, confidenceFloor: confidenceFloor)
        if let refinedOffset {
            return DeviceOffset(
                deviceID: anchor.deviceID, canonicalSampleOffset: refinedOffset, anchorEstimated: false)
        }
        return DeviceOffset(deviceID: anchor.deviceID, canonicalSampleOffset: estimatedOffset, anchorEstimated: true)
    }

    private static func refineOffset(
        reference: [Float], candidate: [Float], estimatedOffset: Int64, searchRadius: Int64, confidenceFloor: Double
    ) -> Int64? {
        var bestOffset = estimatedOffset
        var bestScore = -Double.infinity

        var offset = estimatedOffset - searchRadius
        while offset <= estimatedOffset + searchRadius {
            let score = normalizedCorrelation(reference: reference, candidate: candidate, offset: offset)
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
            offset += 1
        }

        return bestScore >= confidenceFloor ? bestOffset : nil
    }

    /// Pearson-style normalized correlation in `[-1, 1]` between `candidate`
    /// and `reference` shifted by `offset`, over their overlapping samples
    /// only.
    private static func normalizedCorrelation(reference: [Float], candidate: [Float], offset: Int64) -> Double {
        var sumProduct = 0.0
        var sumReferenceSquared = 0.0
        var sumCandidateSquared = 0.0
        var overlapCount = 0

        for candidateIndex in 0..<candidate.count {
            let referenceIndex = Int64(candidateIndex) + offset
            guard referenceIndex >= 0, referenceIndex < reference.count else { continue }
            let referenceSample = Double(reference[Int(referenceIndex)])
            let candidateSample = Double(candidate[candidateIndex])
            sumProduct += referenceSample * candidateSample
            sumReferenceSquared += referenceSample * referenceSample
            sumCandidateSquared += candidateSample * candidateSample
            overlapCount += 1
        }

        guard overlapCount > 0, sumReferenceSquared > 0, sumCandidateSquared > 0 else { return -1 }
        return sumProduct / (sumReferenceSquared.squareRoot() * sumCandidateSquared.squareRoot())
    }
}
