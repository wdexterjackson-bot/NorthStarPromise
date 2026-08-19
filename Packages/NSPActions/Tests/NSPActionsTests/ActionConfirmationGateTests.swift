import Testing

/// I6 gate (docs/10 §2, "I6 — Humans confirm before the world changes").
/// Needs the action outbox and confirmation gate — neither exists yet.
/// Remove `.disabled` and implement when `NSP-048`…`NSP-050` land.
@Suite("I6 gate — action confirmation (NSPActions)")
struct ActionConfirmationGateTests {
    @Test(.disabled("needs the action confirmation gate — lands with NSP-049"))
    func test_actionOutbox_requiresExplicitConfirmation() {
        // An Action cannot be enqueued while any field is .unresolved or
        // .inferred without a confirmation record naming the exact payload
        // hash (docs/10 §2).
    }

    @Test(.disabled("needs the idempotent integration outbox — lands with NSP-050"))
    func test_actionOutbox_replayIsIdempotent() {
        // Replays every outbox message 1-5 times in random order; asserts a
        // single IntegrationReceipt and a single external write per
        // (actionID, destination, revision) key (docs/10 §2).
    }
}
