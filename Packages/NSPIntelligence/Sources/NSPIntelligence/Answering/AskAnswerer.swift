import NSPCore
import NSPPolicy

/// A grounded answer to one Ask question (docs/04 §10.4). Every citation
/// points at a real, already-retrieved chunk's turn range — never a quote
/// the model invented — so `text` alone is never presented as fact without
/// at least one citation backing it (Invariant I4): `citations.isEmpty`
/// pairs with a non-`nil` `refusalReason`, never with standalone `text`.
public struct AskAnswer: Sendable {
    public struct Citation: Sendable, Hashable {
        public let meetingID: MeetingID
        public let turnIDs: [TranscriptTurnID]

        public init(meetingID: MeetingID, turnIDs: [TranscriptTurnID]) {
            self.meetingID = meetingID
            self.turnIDs = turnIDs
        }
    }

    public let text: String
    public let citations: [Citation]
    /// Non-`nil` whenever there's no grounded answer to show — the model
    /// isn't available, nothing was retrieved, or the model answered but
    /// cited none of the provided sources. `text` is empty whenever this is
    /// set.
    public let refusalReason: String?

    public init(text: String, citations: [Citation], refusalReason: String?) {
        self.text = text
        self.citations = citations
        self.refusalReason = refusalReason
    }
}

/// docs/04 §10.4's answering step — takes `HybridRetriever`'s already-
/// authorized, already-real chunks and asks a model which of them answer
/// the question, never inventing new quotes the way summarization/action
/// extraction do (there's no ungrounded-claim risk to check for beyond
/// "did the model actually cite one of the sources it was given").
public protocol AskAnswerer: Sendable {
    func answer(question: String, chunks: [RetrievedChunk]) async throws -> AskAnswer
    func answerRemote(question: String, chunks: [RetrievedChunk], grant: ProcessingGrant) async throws -> AskAnswer
    var availability: ModelAvailability { get }
}
