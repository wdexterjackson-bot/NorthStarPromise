import Testing

@testable import NSPCore

/// Fuzzes 10,000 random command sequences against `MeetingLifecycle` and
/// asserts the invariants docs/02 §3 lists for the state machine. Uses a
/// seeded, deterministic generator (docs/11 §5: "seeded randomness only; a
/// seed is printed on failure") so a failure reproduces exactly.
@Suite("MeetingLifecycle property tests")
struct MeetingLifecyclePropertyTests {
    /// xorshift64*, seedable, deterministic — good enough for fuzzing, not
    /// for anything cryptographic.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    static let seed: UInt64 = 42
    static let sequenceCount = 10_000
    static let stepsPerSequence = 12

    // One case per MeetingCommand — a lookup table would obscure, not
    // simplify, this enumeration.
    // swiftlint:disable:next cyclomatic_complexity
    static func randomCommand(using rng: inout SeededGenerator) -> MeetingCommand {
        switch Int.random(in: 0..<16, using: &rng) {
        case 0: return .arm
        case 1: return .beginRecording
        case 2: return .pause(segmentSampleCount: Int64.random(in: 0...48000, using: &rng))
        case 3: return .resume(gapSampleCount: Int64.random(in: 0...48000, using: &rng))
        case 4:
            return .interrupt(
                cause: InterruptionCause.allCases.randomElement(using: &rng) ?? .otherApp,
                segmentSampleCount: Int64.random(in: 0...48000, using: &rng))
        case 5: return .resolveInterruptionResume(gapSampleCount: Int64.random(in: 0...48000, using: &rng))
        case 6: return .resolveInterruptionRecoverable
        case 7:
            let sampleCount = Bool.random(using: &rng) ? Int64.random(in: 0...48000, using: &rng) : nil
            return .finalize(finalSegmentSampleCount: sampleCount)
        case 8: return .saveRaw
        case 9: return .beginProcessing
        case 10: return .completeProcessing(success: Bool.random(using: &rng))
        case 11: return .approve
        case 12: return .edit
        case 13: return .share
        case 14: return .restore
        default: return .purge
        }
    }

    @Test func test_randomCommandSequences_neverViolateStateMachineInvariants() {
        var rng = SeededGenerator(seed: Self.seed)

        for sequenceIndex in 0..<Self.sequenceCount {
            var lifecycle = MeetingLifecycle()

            for _ in 0..<Self.stepsPerSequence {
                let command = Self.randomCommand(using: &rng)
                let before = lifecycle

                let result = Result { try MeetingLifecycle.transition(from: lifecycle, command: command) }

                switch result {
                case .failure:
                    // A rejected command must never mutate state — the
                    // property-test analog of "never a corrupt manifest"
                    // (docs/02 §3).
                    #expect(
                        lifecycle == before,
                        "seed \(Self.seed) sequence \(sequenceIndex): rejected command changed state")
                    continue
                case .success(let next):
                    lifecycle = next
                }

                // INV-1: .recording is only reachable with an open segment
                // (the state-machine shape of Invariant I1).
                if lifecycle.state == .recording {
                    #expect(
                        lifecycle.hasOpenSegment,
                        "seed \(Self.seed) sequence \(sequenceIndex): entered .recording with no open segment")
                }

                // INV-2: closed segment sequence numbers are 0..<count —
                // pause/resume never reuses or skips one ("N+1 ordered
                // segments... never overwrites a file", docs/02 §3).
                #expect(
                    lifecycle.closedSegments.map(\.sequence) == Array(0..<lifecycle.closedSegments.count),
                    "seed \(Self.seed) sequence \(sequenceIndex): segment sequence numbers were reused or skipped"
                )

                // INV-3: canonical duration == Σ closed segment sample counts
                // (docs/02 §3).
                let expected = lifecycle.closedSegments.reduce(Int64(0)) { $0 + $1.sampleCount }
                #expect(
                    lifecycle.recordedSampleCount == expected,
                    "seed \(Self.seed) sequence \(sequenceIndex): recordedSampleCount drifted from Σ segments")

                // INV-3b: a gap can only follow a segment that was actually
                // closed by a pause/interruption.
                #expect(
                    lifecycle.gapSampleCounts.count <= lifecycle.closedSegments.count,
                    "seed \(Self.seed) sequence \(sequenceIndex): more gaps recorded than closed segments")
            }
        }
    }

    @Test func test_replayingSameCommand_isIdempotent() {
        // Invariant "replaying any transfer or job message produces no
        // duplicate rows" (docs/02 §3), at this layer: `transition` is a
        // pure function, so applying the same command to the same starting
        // value twice must yield the same result both times — no hidden
        // counter, no accumulating duplicate effect.
        let lifecycle = MeetingLifecycle()

        let first = try? MeetingLifecycle.transition(from: lifecycle, command: .arm)
        let second = try? MeetingLifecycle.transition(from: lifecycle, command: .arm)

        #expect(first == second)
    }

    @Test func test_illegalCommand_appliedTwice_neverMutatesState() {
        let lifecycle = MeetingLifecycle()  // .ready

        #expect(throws: MeetingLifecycleError.self) {
            try MeetingLifecycle.transition(from: lifecycle, command: .approve)
        }
        #expect(throws: MeetingLifecycleError.self) {
            try MeetingLifecycle.transition(from: lifecycle, command: .approve)
        }
    }
}
