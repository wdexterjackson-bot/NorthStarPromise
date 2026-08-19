/// The meeting lifecycle state machine (docs/02 §3, NSP-007). Pure value
/// type, no I/O — real segment durability is `NSPMedia`'s job (NSP-014,
/// NSP-020…022) and has its own hardware-backed invariant tests. What this
/// type guarantees structurally:
///
/// - `.recording` is only reachable through a command that also opens a
///   segment, so `state == .recording` implies `hasOpenSegment` always
///   (Invariant I1's shape, at the state-machine level).
/// - Closed segment sequence numbers are always `0..<closedSegments.count`
///   — pause/resume never reuses or skips one.
/// - `recordedSampleCount` is always exactly Σ closed segment sample counts.
/// - `transition(from:command:)` is a pure function: an illegal command
///   never mutates its input, and replaying the same command against the
///   same starting value always produces the same result.
///
/// Only the transitions explicitly named in docs/02 §3 are legal. States the
/// table lists only as *targets* of the Archived/Deleted row — Recoverable,
/// SavedRaw, PartialFailure, Approved, Edited, Shared, Restored, Purged — are
/// terminal here; the doc does not specify what transitions into
/// Archived/Deleted, so this machine does not invent one (docs/11 §12 — fix
/// the doc, don't guess). A repository may still construct a
/// `MeetingLifecycle` directly in any state, e.g. to represent a
/// soft-deleted meeting read back from storage.
public struct MeetingLifecycle: Sendable, Hashable {
    public struct ClosedSegment: Sendable, Hashable {
        public let sequence: Int
        public let sampleCount: Int64
    }

    public private(set) var state: MeetingState
    public private(set) var hasOpenSegment: Bool
    public private(set) var closedSegments: [ClosedSegment]
    public private(set) var gapSampleCounts: [Int64]
    public private(set) var recordedSampleCount: Int64

    public init(state: MeetingState = .ready) {
        self.state = state
        self.hasOpenSegment = false
        self.closedSegments = []
        self.gapSampleCounts = []
        self.recordedSampleCount = 0
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// The exhaustive transition function. Legal moves are the explicit
    /// cases; everything else is `.illegalTransition` — that catch-all *is*
    /// the exhaustiveness the ticket asks for: every `(state, command)` pair
    /// not named in docs/02 §3 is deliberately, uniformly rejected rather
    /// than left to crash or silently no-op. Its size and branch count come
    /// directly from the one-case-per-edge table in docs/02 §3; splitting it
    /// would trade a single source of truth for indirection, so complexity
    /// and length checks are suppressed here, NSP-007.
    public static func transition(
        from lifecycle: MeetingLifecycle,
        command: MeetingCommand
    ) throws(MeetingLifecycleError) -> MeetingLifecycle {
        var next = lifecycle

        switch (lifecycle.state, command) {
        case (.ready, .arm):
            next.state = .arming

        case (.arming, .beginRecording):
            next.state = .recording
            next.hasOpenSegment = true

        case (.arming, .fail(let reason)):
            next.state = .failed(reason: reason)

        case (.recording, .pause(let sampleCount)):
            next.closeCurrentSegment(sampleCount: sampleCount)
            next.state = .paused

        case (.recording, .finalize(let sampleCount)):
            guard let sampleCount else {
                throw .invalidPayload(reason: "an open segment must be closed before finalizing from .recording")
            }
            next.closeCurrentSegment(sampleCount: sampleCount)
            next.state = .finalizing

        case (.recording, .interrupt(_, let sampleCount)):
            next.closeCurrentSegment(sampleCount: sampleCount)
            next.state = .interrupted

        case (.paused, .resume(let gapSampleCount)):
            next.gapSampleCounts.append(gapSampleCount)
            next.hasOpenSegment = true
            next.state = .recording

        case (.paused, .finalize(let sampleCount)):
            guard sampleCount == nil else {
                throw .invalidPayload(reason: "no segment is open while .paused; pass finalSegmentSampleCount: nil")
            }
            next.state = .finalizing

        case (.interrupted, .resolveInterruptionResume(let gapSampleCount)):
            next.gapSampleCounts.append(gapSampleCount)
            next.hasOpenSegment = true
            next.state = .recording

        case (.interrupted, .finalize(let sampleCount)):
            guard sampleCount == nil else {
                throw .invalidPayload(
                    reason: "no segment is open while .interrupted; pass finalSegmentSampleCount: nil")
            }
            next.state = .finalizing

        case (.interrupted, .resolveInterruptionRecoverable):
            next.state = .recoverable

        case (.finalizing, .beginProcessing):
            next.state = .processing

        case (.finalizing, .saveRaw):
            next.state = .savedRaw

        case (.processing, .completeProcessing(let success)):
            next.state = success ? .readyForReview : .partialFailure

        case (.readyForReview, .approve):
            next.state = .approved

        case (.readyForReview, .edit):
            next.state = .edited

        case (.readyForReview, .share):
            next.state = .shared

        case (.archived, .restore), (.deleted, .restore):
            next.state = .restored

        case (.archived, .purge), (.deleted, .purge):
            next.state = .purged

        default:
            throw .illegalTransition(from: lifecycle.state, command: command)
        }

        return next
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    private mutating func closeCurrentSegment(sampleCount: Int64) {
        closedSegments.append(ClosedSegment(sequence: closedSegments.count, sampleCount: sampleCount))
        recordedSampleCount += sampleCount
        hasOpenSegment = false
    }
}
