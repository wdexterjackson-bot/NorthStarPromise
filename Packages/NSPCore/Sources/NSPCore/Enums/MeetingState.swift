/// A meeting's lifecycle state (docs/02 §3). This is the vocabulary only —
/// the exhaustive transition function and its property tests are NSP-007.
public enum MeetingState: Sendable, Hashable, Codable {
    case ready
    case arming
    case recording
    case paused
    case interrupted
    case finalizing
    case processing
    case readyForReview
    case approved
    case edited
    case shared
    case archived
    case deleted
    case restored
    case purged
    case recoverable
    case savedRaw
    case partialFailure
    case failed(reason: String)
}
