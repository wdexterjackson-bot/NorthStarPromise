/// A segment's journey from the capturing device to a verified, receipted
/// copy elsewhere (docs/02 §2, `Segment.transferState`; docs/03 §8).
public enum TransferState: Sendable, Hashable, Codable {
    case local
    case queued
    case inFlight
    case receivedUnverified
    case verified
    case reclaimed
    case failed(reason: String)
}
