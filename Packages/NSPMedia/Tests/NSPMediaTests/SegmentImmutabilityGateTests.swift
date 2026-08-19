import Testing

/// I3 gate (docs/10 §2, "I3 — Segments are immutable and content-addressed").
/// Needs `NSPMedia.Segmenter` and its integrity/repair machinery — neither
/// exists yet. Remove `.disabled` and implement when `NSP-020`, `NSP-021`,
/// and `NSP-055` land.
@Suite("I3 gate — segment immutability (NSPMedia)")
struct SegmentImmutabilityGateTests {
    @Test(.disabled("needs NSPMedia.Segmenter + RecordingFileSystem fake — lands with NSP-020, NSP-021"))
    func test_segment_afterClose_isNeverReopenedForWriting() {
        // Asserts no write handle is ever opened on a path already renamed
        // to its final name (docs/10 §2).
    }

    @Test(.disabled("needs the truncated-tail repair path — lands with NSP-055"))
    func test_segment_hashStability_acrossRepair() {
        // A repaired tail must produce a *new* segmentID and hash rather
        // than mutating the original (docs/10 §2).
    }
}
