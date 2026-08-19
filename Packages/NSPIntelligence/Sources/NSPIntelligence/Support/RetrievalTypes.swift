import Foundation
import NSPCore

/// The mandatory, explicit scope every Ask session opens with (docs/04
/// §10.1, verbatim list) — there is no default "everything." Required by
/// `RetrieverProtocol.retrieve`; there is no unscoped entry point (docs/04
/// §10.2).
public enum AskScope: Sendable, Hashable {
    case meeting(MeetingID)
    case series(String)
    case projectOrTag(String)
    case workspace(WorkspaceID)
    case dateRange(ClosedRange<Date>)
    case selectedMeetings(Set<MeetingID>)
}

/// A query into `RetrieverProtocol` (docs/04 §10.3's hybrid-retrieval
/// pipeline: normalize, expand with glossary aliases, fuse FTS5 + vector).
public struct RetrievalQuery: Sendable, Hashable {
    public let text: String
    /// K in docs/04 §10.3's "top-K (K ≈ 24, token-budgeted)".
    public let maxResults: Int

    public init(text: String, maxResults: Int = 24) {
        self.text = text
        self.maxResults = maxResults
    }
}

/// One turn-aligned chunk with overlap, so a citation is always a real turn
/// range (docs/04 §10.3).
public struct RetrievedChunk: Sendable, Hashable {
    public let meetingID: MeetingID
    public let turnIDs: [TranscriptTurnID]
    public let text: String
    public let score: Double

    public init(meetingID: MeetingID, turnIDs: [TranscriptTurnID], text: String, score: Double) {
        self.meetingID = meetingID
        self.turnIDs = turnIDs
        self.text = text
        self.score = score
    }
}
