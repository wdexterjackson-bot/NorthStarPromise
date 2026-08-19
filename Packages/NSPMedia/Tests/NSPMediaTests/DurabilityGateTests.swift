import Testing

/// I1 gate, filesystem half (docs/10 §2, "I1 — Durability before
/// acknowledgement"). Needs `NSPMedia.CaptureEngine` and a fake `FileSystem`
/// that records fsync ordering — neither exists yet.
///
/// This test is written now, disabled, so the gate is visible in the test
/// tree from M0 onward (docs/08, "failing-by-absence... they start as
/// failing-by-absence tests that turn green as the subsystem lands") rather
/// than silently appearing only once someone remembers to add it. Remove
/// `.disabled` and implement the body when `NSP-018`…`NSP-022` land the
/// capture engine and segmenter.
@Suite("I1 gate — capture durability (NSPMedia)")
struct DurabilityGateTests {
    @Test(
        .disabled(
            "needs NSPMedia.CaptureEngine + RecordingFileSystem fake — lands with NSP-018…NSP-022")
    )
    func test_captureSession_startWithSlowFsync_doesNotEnterRecordingBeforeHeaderDurable() {
        // Fails if the state machine emits `.recording` before the fake
        // FileSystem records an fsync on segment 0's header (docs/10 §2).
    }
}
