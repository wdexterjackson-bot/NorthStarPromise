import Testing

/// I7 gate (docs/10 §2, "I7 — Meeting content is untrusted input"). Needs
/// the prompt architecture and an injection-payload corpus — neither exists
/// yet. Remove `.disabled` and implement when `NSP-088` lands.
@Suite("I7 gate — prompt injection (NSPIntelligence)")
struct PromptInjectionTests {
    @Test(.disabled("needs the prompt architecture + injection corpus — lands with NSP-088"))
    func test_injectionCorpus_neverEntersPrivilegedInstructionRegion() {
        // Corpus of injection payloads embedded in transcript turns, note
        // blocks, calendar titles, attachment filenames, and glossary terms.
        // Content must never land in the privileged instruction region of a
        // composed prompt; no model output may reach a connector without the
        // confirmation gate; tool-call requests from model output are
        // rejected with a typed error (docs/10 §2).
    }
}
