import Testing

/// I5 gate, behavioural half (docs/10 §2, "I5 — Local-only means
/// local-only", gate 2 of 2: `PRV-001`). The static half —
/// `test_architecture_networkImportsRestricted` — is implemented today in
/// `NSPCoreTests/ArchitectureTests.swift`. This one needs a recording proxy,
/// a fixture with watermarked audio and sentinel strings, and a full
/// record→process→review→export path — none of which exist yet. Remove
/// `.disabled` and implement when `NSP-052` lands.
@Suite("I5 gate — network-content audit (PRV-001)")
struct NetworkAuditTests {
    @Test(.disabled("needs a full record→process→review→export path + recording proxy — lands with NSP-052"))
    func test_localOnlyMeeting_egressesZeroContentBytes() {
        // Launches the app with ProcessingMode forced to .localOnly, points
        // it at a recording HTTP/HTTPS proxy, drives a full
        // record→process→review→export cycle against a fixture whose audio
        // and title/attendees contain unique watermark/sentinel tokens, and
        // asserts zero occurrences of any watermark or sentinel in the
        // complete request corpus, and zero requests to non-allow-listed
        // hosts (docs/10 §2).
    }
}
