/// Every event that can drive a `MeetingLifecycle` forward (docs/02 §3).
/// Sample-count payloads close the segment open at the moment of the
/// command, so the lifecycle's segment bookkeeping never depends on wall
/// clock or an external `Date()` (docs/11 §4).
public enum MeetingCommand: Sendable, Hashable {
    case arm
    /// Opens segment 0. The caller (`NSPMedia`) must only issue this after
    /// the segment's header is durably fsync'd (Invariant I1) — this type
    /// cannot verify bytes on disk itself; `NSP-022`'s filesystem-spy test
    /// verifies that production callers uphold the precondition.
    case beginRecording
    case pause(segmentSampleCount: Int64)
    case resume(gapSampleCount: Int64)
    case interrupt(cause: InterruptionCause, segmentSampleCount: Int64)
    case resolveInterruptionResume(gapSampleCount: Int64)
    case resolveInterruptionRecoverable
    /// `finalSegmentSampleCount` closes the currently open segment; pass
    /// `nil` only when no segment is open (finalizing from `.paused` or
    /// `.interrupted`, where the last segment was already closed).
    case finalize(finalSegmentSampleCount: Int64?)
    case saveRaw
    case beginProcessing
    case completeProcessing(success: Bool)
    case approve
    case edit
    case share
    case restore
    case purge
    case fail(reason: String)
}

/// Why a command was rejected. Every case is typed and exhaustive
/// (docs/11 §2) — no `NSError`, no stringly-typed catch-all.
public enum MeetingLifecycleError: Error, Sendable, Hashable {
    /// The table in docs/02 §3 does not allow this command from this state.
    case illegalTransition(from: MeetingState, command: MeetingCommand)
    /// The command's payload contradicts the lifecycle's own bookkeeping
    /// (e.g. closing a segment that isn't open).
    case invalidPayload(reason: String)
}
