import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy

/// The real `RetrieverProtocol` (docs/04 §10.3): resolves + authorizes
/// `scope` first (no unscoped path, docs/04 §10.2), then fuses FTS5's
/// lexical hits with the on-device embedder's vector hits via Reciprocal
/// Rank Fusion — the standard, parameter-light way to combine two
/// differently-scaled rankers without hand-tuning a weight between them.
/// Brute-force cosine over `EmbeddingRepository.fetchCandidates`, not an
/// ANN index — a deliberate v1 choice given this app's realistic per-device
/// corpus size (`EmbeddingRepository`'s own doc comment).
public struct HybridRetriever: RetrieverProtocol {
    private let ftsQueryService: any FTSQueryService
    private let embedder: any EmbedderProtocol
    private let embeddingRepository: any EmbeddingRepository
    private let transcriptTurnRepository: any TranscriptTurnRepository
    private let authorizationResolver: AskAuthorizationResolver
    /// This app creates exactly one workspace per install (`AppEnvironment
    /// .bootstrap()`) — injected once at construction rather than added as
    /// a per-call parameter, since `RetrieverProtocol.retrieve` doesn't
    /// carry one (`AskScope.dateRange`/`.workspace` both need it to resolve
    /// against `AskAuthorizationResolver`).
    private let currentWorkspaceID: WorkspaceID

    /// The standard RRF constant (Cormack et al.) — large enough that a
    /// single ranker's top hit doesn't dominate the fused score outright,
    /// small enough that rank position still matters more than which list
    /// it came from.
    private static let rrfConstant = 60.0

    public init(
        ftsQueryService: any FTSQueryService, embedder: any EmbedderProtocol,
        embeddingRepository: any EmbeddingRepository, transcriptTurnRepository: any TranscriptTurnRepository,
        authorizationResolver: AskAuthorizationResolver, currentWorkspaceID: WorkspaceID
    ) {
        self.ftsQueryService = ftsQueryService
        self.embedder = embedder
        self.embeddingRepository = embeddingRepository
        self.transcriptTurnRepository = transcriptTurnRepository
        self.authorizationResolver = authorizationResolver
        self.currentWorkspaceID = currentWorkspaceID
    }

    public func retrieve(_ query: RetrievalQuery, scope: AskScope) async throws -> [RetrievedChunk] {
        let meetingIDs = try await authorizationResolver.resolve(scope, currentWorkspaceID: currentWorkspaceID)
        guard !meetingIDs.isEmpty else { return [] }

        async let ftsHits = ftsQueryService.search(query: query.text, meetingIDs: meetingIDs, limit: query.maxResults)
        async let vectorHits = Self.embeddingHits(
            query: query, meetingIDs: meetingIDs, embedder: embedder, embeddingRepository: embeddingRepository)

        var turnsCache: [MeetingID: [TranscriptTurn]] = [:]
        let expandedFTSHits = try await Self.expandTranscriptHits(
            try await ftsHits, transcriptTurnRepository: transcriptTurnRepository, turnsCache: &turnsCache)

        return Self.fuse(ftsChunks: expandedFTSHits, vectorChunks: try await vectorHits, limit: query.maxResults)
    }

    public func retrieveRemote(
        _ query: RetrievalQuery, scope: AskScope, grant: ProcessingGrant
    ) async throws -> [RetrievedChunk] {
        throw AskRetrieverError.unimplemented
    }

    /// Only `.transcript` FTS hits feed the chunk pipeline — `.notes`/
    /// `.insight` hits aren't turn-ranged the same way (docs/04 §10.3's
    /// citations are transcript turn ranges; see `FTSHit`'s own doc
    /// comment). Each surviving hit is expanded to the same chunk
    /// boundaries `EmbeddingIndexer` wrote, via `TurnChunker
    /// .enclosingWindow`, so a lexical and a vector hit on overlapping text
    /// fuse into one result instead of double-counting.
    private static func expandTranscriptHits(
        _ hits: [FTSHit], transcriptTurnRepository: any TranscriptTurnRepository,
        turnsCache: inout [MeetingID: [TranscriptTurn]]
    ) async throws -> [RetrievedChunk] {
        var results: [RetrievedChunk] = []
        for hit in hits where hit.source == .transcript {
            guard let turnUUID = UUID(uuidString: hit.sourceRowID) else { continue }
            let turnID = TranscriptTurnID(rawValue: turnUUID)
            let turns: [TranscriptTurn]
            if let cached = turnsCache[hit.meetingID] {
                turns = cached
            } else {
                turns = try await transcriptTurnRepository.fetchAll(owner: .meeting(hit.meetingID))
                turnsCache[hit.meetingID] = turns
            }
            guard let window = TurnChunker.enclosingWindow(for: turnID, in: turns) else { continue }
            results.append(
                RetrievedChunk(meetingID: hit.meetingID, turnIDs: window.turnIDs, text: window.text, score: 0))
        }
        return results
    }

    /// Embeds the query once and scores every authorized candidate by
    /// cosine similarity — `nil`/empty whenever the on-device embedder
    /// isn't available, so a missing model degrades Ask to lexical-only
    /// results rather than throwing.
    private static func embeddingHits(
        query: RetrievalQuery, meetingIDs: Set<MeetingID>, embedder: any EmbedderProtocol,
        embeddingRepository: any EmbeddingRepository
    ) async throws -> [RetrievedChunk] {
        guard embedder.availability == .available else { return [] }
        guard let queryVector = try await embedder.embedOnDevice([query.text]).first?.vector else { return [] }
        let candidates = try await embeddingRepository.fetchCandidates(
            meetingIDs: meetingIDs, modelIdentifier: embedder.modelIdentifier)
        return
            candidates
            .map { candidate in
                RetrievedChunk(
                    meetingID: candidate.meetingID, turnIDs: candidate.turnIDs, text: candidate.chunkText,
                    score: Self.cosineSimilarity(queryVector, candidate.vector))
            }
            .sorted { $0.score > $1.score }
            .prefix(query.maxResults)
            .map { $0 }
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var normLHS: Float = 0
        var normRHS: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            normLHS += lhs[index] * lhs[index]
            normRHS += rhs[index] * rhs[index]
        }
        guard normLHS > 0, normRHS > 0 else { return 0 }
        return Double(dot / (normLHS.squareRoot() * normRHS.squareRoot()))
    }

    /// Reciprocal Rank Fusion over two already-ranked lists, deduped on
    /// `(meetingID, turnIDs)` so the same chunk found by both rankers
    /// contributes both terms rather than appearing twice.
    private static func fuse(
        ftsChunks: [RetrievedChunk], vectorChunks: [RetrievedChunk], limit: Int
    ) -> [RetrievedChunk] {
        var scores: [String: Double] = [:]
        var chunksByKey: [String: RetrievedChunk] = [:]

        func accumulate(_ chunks: [RetrievedChunk]) {
            for (index, chunk) in chunks.enumerated() {
                let key = Self.key(for: chunk)
                scores[key, default: 0] += 1.0 / (Self.rrfConstant + Double(index + 1))
                chunksByKey[key] = chunk
            }
        }
        accumulate(ftsChunks)
        accumulate(vectorChunks)

        return
            scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { key, score in
                chunksByKey[key].map {
                    RetrievedChunk(meetingID: $0.meetingID, turnIDs: $0.turnIDs, text: $0.text, score: score)
                }
            }
    }

    private static func key(for chunk: RetrievedChunk) -> String {
        let turnKey = chunk.turnIDs.map { $0.rawValue.uuidString }.sorted().joined(separator: ",")
        return "\(chunk.meetingID.rawValue.uuidString)|\(turnKey)"
    }
}

public enum AskRetrieverError: Error, Sendable, Hashable {
    /// No backend exists yet — `retrieveRemote` has nowhere to call.
    case unimplemented
}
