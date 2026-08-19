import Testing

/// I2 gate (docs/10 §2, "I2 — The capturing device owns the truth"). Needs
/// the transfer outbox and reclamation policy — neither exists yet. Remove
/// `.disabled` and implement when `NSP-029`…`NSP-031` and `NSP-061` land.
@Suite("I2 gate — reclamation (NSPTransfer)")
struct ReclamationTests {
    @Test(.disabled("needs the transfer outbox + WatchConnectivity fake — lands with NSP-029…NSP-031"))
    func test_transfer_reclamation_requiresVerifiedReceipt() {
        // A Segment may leave .verified for .reclaimed only when a verified
        // receipt exists and the retention grace has elapsed (docs/10 §2).
    }

    @Test(.disabled("needs the reclamation policy — lands with NSP-061"))
    func test_transfer_neverDeletesBeforeVerification() {
    }

    @Test(.disabled("source-scan audit of NSPTransfer + NSPMedia delete calls — lands with NSP-061"))
    func test_architecture_allFilesystemDeletesRouteThroughReclamationPolicy() {
        // Companion audit test: walks NSPTransfer and NSPMedia sources for
        // any filesystem delete call not routed through ReclamationPolicy
        // and fails on a match (docs/10 §2).
    }
}
