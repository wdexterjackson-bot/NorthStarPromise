import Foundation
import NSPCore
import NSPPersistence

/// Populates the `embedding` table for one meeting's transcript turns —
/// nothing else in this codebase calls `EmbedderProtocol.embedOnDevice`
/// today; this is the missing wiring Ask's vector half depends on.
///
/// v1 scope: only `transcript_turn` content gets vector-embedded.
/// `note_block`/`insight` participate in FTS only (`Migration004`'s
/// triggers already cover them) — vector parity for notes/insights is a
/// flagged fast-follow, not this pass.
public struct EmbeddingIndexer: Sendable {
    private let embedder: any EmbedderProtocol
    private let embeddingRepository: any EmbeddingRepository

    public init(embedder: any EmbedderProtocol, embeddingRepository: any EmbeddingRepository) {
        self.embedder = embedder
        self.embeddingRepository = embeddingRepository
    }

    /// No-ops (not an error) when the embedder isn't available — matching
    /// `LiveOnDeviceSummarizer`'s degrade-not-fail shape; a meeting simply
    /// stays vector-unsearchable (still FTS-searchable) until the model is.
    public func index(meetingID: MeetingID, turns: [TranscriptTurn], at date: Date) async throws {
        guard embedder.availability == .available else { return }

        let windows = TurnChunker.windows(for: turns)
        guard !windows.isEmpty else { return }

        let embeddings = try await embedder.embedOnDevice(windows.map(\.text))
        guard embeddings.count == windows.count else { return }

        let chunks = zip(windows, embeddings).map { window, embedding in
            EmbeddingChunkInput(
                turnIDs: window.turnIDs, sampleStart: window.sampleRange.startSample,
                sampleEnd: window.sampleRange.endSample, text: window.text, vector: embedding.vector)
        }
        try await embeddingRepository.replaceAll(
            meetingID: meetingID, chunks: chunks, modelIdentifier: embedder.modelIdentifier, at: date)
    }
}
