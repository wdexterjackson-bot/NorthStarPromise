import Testing

@testable import NSPCore

/// The I1 invariant gate at the state-machine layer (docs/10 §2, "I1 —
/// Durability before acknowledgement";
/// `test_stateMachine_ackOrdering_property`). The other two I1 gates named
/// in docs/10 §2 — the filesystem-spy test in `NSPMediaTests` and the
/// Watch-UI snapshot test — need `NSPMedia`'s capture engine (NSP-018…022)
/// and the Watch UI (NSP-026), which don't exist yet; see their `.disabled`
/// stubs at the documented locations.
@Suite("I1 gate — ack ordering")
struct LifecycleInvariantTests {
    @Test func test_stateMachine_ackOrdering_property() {
        // Random arm/beginRecording/fail orderings; asserts the durable-write
        // signal (`hasOpenSegment`) always precedes the first `.recording`
        // observation in the emitted state log — there is no reachable
        // lifecycle value where `.recording` appears without it.
        var rng = MeetingLifecyclePropertyTests.SeededGenerator(seed: 7)

        for _ in 0..<1000 {
            var lifecycle = MeetingLifecycle()
            var observedRecordingBeforeDurableWrite = false

            for _ in 0..<8 {
                let command = MeetingLifecyclePropertyTests.randomCommand(using: &rng)
                guard let next = try? MeetingLifecycle.transition(from: lifecycle, command: command)
                else { continue }
                lifecycle = next

                if lifecycle.state == .recording && !lifecycle.hasOpenSegment {
                    observedRecordingBeforeDurableWrite = true
                }
            }

            #expect(!observedRecordingBeforeDurableWrite)
        }
    }
}
