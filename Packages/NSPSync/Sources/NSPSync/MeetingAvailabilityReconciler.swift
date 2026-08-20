import NSPCore

/// Computes a meeting's `Availability` from what's locally known about its
/// segments (docs/02 §6: "A meeting is usable before all assets arrive:
/// show `Partial` with the exact missing segments and the device that last
/// held them"). Pure logic — no CloudKit dependency — because the
/// distinction that matters here is metadata vs. content, not local vs.
/// remote: a segment whose `CD_Segment` record has synced but whose
/// `CKAsset` audio hasn't downloaded yet (`localURL == nil`) is exactly
/// what "missing" means.
///
/// A sequence with no synced metadata at all can't produce a `SegmentRef`
/// (there's no `segmentID`/`deviceID` to report) — that's a gap the
/// segmenter/transfer layer's own guarantees are responsible for
/// surfacing (docs/03 §3.2's "a gap means a lost segment"), not something
/// this reconciler can detect from Segment rows alone.
public enum MeetingAvailabilityReconciler {
    public static func availability(for knownSegments: [Segment]) -> Availability {
        guard !knownSegments.isEmpty else { return .complete }

        let missing =
            knownSegments
            .filter { $0.localURL == nil }
            .sorted { $0.sequence < $1.sequence }
            .map { SegmentRef(segmentID: $0.segmentID, deviceID: $0.deviceID, sequence: $0.sequence) }

        return missing.isEmpty ? .complete : .partial(missing: missing)
    }
}
