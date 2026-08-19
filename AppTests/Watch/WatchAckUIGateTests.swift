import Testing

/// I1 gate, UI half (docs/10 §2, "I1 — Durability before acknowledgement",
/// `test_watchStartUI_noSavedAffordanceBeforeSeal`). Needs the Watch
/// Ready/Recording/Paused/Finalizing UI — doesn't exist yet. Remove
/// `.disabled` and implement when `NSP-026` lands.
@Suite("I1 gate — Watch ack UI")
struct WatchAckUIGateTests {
    @Test(.disabled("needs the Watch capture UI — lands with NSP-026"))
    func test_watchStartUI_noSavedAffordanceBeforeSeal() {
        // Snapshot + accessibility-tree assertion: no view exposes
        // "Recording" or "Saved" text or haptic while the injected segmenter
        // is blocked (docs/10 §2).
    }
}
