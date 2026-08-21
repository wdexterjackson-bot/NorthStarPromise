import Foundation
@preconcurrency import GRDB
import NSPCore

/// One chunk to embed and persist — `NSPIntelligence`'s `EmbeddingIndexer`
/// builds these from `TurnChunker.ChunkWindow`s; kept here rather than
/// imported from `NSPIntelligence` so this protocol stays free of that
/// package's types (wrong dependency direction).
public struct EmbeddingChunkInput: Sendable {
    public let turnIDs: [TranscriptTurnID]
    public let sampleStart: Int64
    public let sampleEnd: Int64
    public let text: String
    public let vector: [Float]

    public init(turnIDs: [TranscriptTurnID], sampleStart: Int64, sampleEnd: Int64, text: String, vector: [Float]) {
        self.turnIDs = turnIDs
        self.sampleStart = sampleStart
        self.sampleEnd = sampleEnd
        self.text = text
        self.vector = vector
    }
}

/// CRUD for the `embedding` table — Ask's vector-retrieval half (docs/04
/// §10.3, NSP-089). Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol EmbeddingRepository: Sendable {
    /// Full delete-then-reinsert for `meetingID` — same "replace, not diff"
    /// pattern as `GRDBNoteBlockRepository`/`TranscriptTurnRepository`, so
    /// re-indexing after a transcript edit or an embedder-model change is a
    /// clean overwrite, never an accumulation.
    func replaceAll(meetingID: MeetingID, chunks: [EmbeddingChunkInput], modelIdentifier: String, at date: Date)
        async throws
    /// Raw candidate rows for a scoped query, filtered to the *current*
    /// embedder's `modelIdentifier` — vectors from a retired model are
    /// silently excluded rather than requiring an active migration
    /// (`EmbedderProtocol.modelIdentifier`'s own doc comment).
    func fetchCandidates(meetingIDs: Set<MeetingID>, modelIdentifier: String) async throws -> [EmbeddingCandidateRow]
    func delete(meetingID: MeetingID) async throws
}

public struct GRDBEmbeddingRepository: EmbeddingRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func replaceAll(
        meetingID: MeetingID, chunks: [EmbeddingChunkInput], modelIdentifier: String, at date: Date
    ) async throws {
        try await dbWriter.write { db in
            try EmbeddingRow.filter(Column("meeting_id") == meetingID.rawValue.uuidString).deleteAll(db)
            for chunk in chunks {
                let row = try EmbeddingRow(
                    meetingID: meetingID, turnIDs: chunk.turnIDs, sampleStart: chunk.sampleStart,
                    sampleEnd: chunk.sampleEnd, chunkText: chunk.text, modelIdentifier: modelIdentifier,
                    vector: chunk.vector, createdAt: date, updatedAt: date, rowRevision: 1)
                try row.insert(db)
            }
        }
    }

    public func fetchCandidates(
        meetingIDs: Set<MeetingID>, modelIdentifier: String
    ) async throws -> [EmbeddingCandidateRow] {
        guard !meetingIDs.isEmpty else { return [] }
        let ids = meetingIDs.map { $0.rawValue.uuidString }
        return try await dbWriter.read { db in
            try EmbeddingRow
                .filter(ids.contains(Column("meeting_id")))
                .filter(Column("model_identifier") == modelIdentifier)
                .filter(Column("excluded_from_memory") == false)
                .fetchAll(db)
                .map { try $0.asCandidate() }
        }
    }

    public func delete(meetingID: MeetingID) async throws {
        try await dbWriter.write { db in
            _ = try EmbeddingRow.filter(Column("meeting_id") == meetingID.rawValue.uuidString).deleteAll(db)
        }
    }
}
