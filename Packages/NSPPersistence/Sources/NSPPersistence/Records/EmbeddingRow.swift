import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `embedding` table (`Migration001`'s "local vector index").
/// `vector` round-trips through the BLOB column as raw little-endian
/// `Float32` bytes — a private encode/decode local to this record, not a
/// global `[Float]: DatabaseValueConvertible` conformance (too broad a hook
/// to hang off a primitive type for one table's need).
struct EmbeddingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embedding"

    var embeddingID: String
    var meetingID: String
    var turnIDsJSON: String
    var sampleStart: Int64
    var sampleEnd: Int64
    var chunkText: String
    var modelIdentifier: String
    var vector: Data
    var excludedFromMemory: Bool
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case embeddingID = "embedding_id"
        case meetingID = "meeting_id"
        case turnIDsJSON = "turn_ids_json"
        case sampleStart = "sample_start"
        case sampleEnd = "sample_end"
        case chunkText = "chunk_text"
        case modelIdentifier = "model_identifier"
        case vector
        case excludedFromMemory = "excluded_from_memory"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(
        meetingID: MeetingID, turnIDs: [TranscriptTurnID], sampleStart: Int64, sampleEnd: Int64, chunkText: String,
        modelIdentifier: String, vector: [Float], createdAt: Date, updatedAt: Date, rowRevision: Int
    ) throws {
        self.embeddingID = UUID().uuidString
        self.meetingID = meetingID.rawValue.uuidString
        self.turnIDsJSON = try Self.encodeTurnIDs(turnIDs)
        self.sampleStart = sampleStart
        self.sampleEnd = sampleEnd
        self.chunkText = chunkText
        self.modelIdentifier = modelIdentifier
        self.vector = Self.encode(vector)
        self.excludedFromMemory = false
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    /// Raw candidate row for `HybridRetriever`'s brute-force cosine scan —
    /// no similarity math here, `NSPPersistence` never imports `Embedding`
    /// or knows what "similarity" means; the caller scores in Swift.
    func asCandidate() throws -> EmbeddingCandidateRow {
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        let turnIDs = try Self.decodeTurnIDs(turnIDsJSON)
        return EmbeddingCandidateRow(
            meetingID: MeetingID(rawValue: meetingUUID), turnIDs: turnIDs, sampleStart: sampleStart,
            sampleEnd: sampleEnd, chunkText: chunkText, vector: Self.decode(vector))
    }

    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    private static func encodeTurnIDs(_ turnIDs: [TranscriptTurnID]) throws -> String {
        let strings = turnIDs.map { $0.rawValue.uuidString }
        let data = try JSONEncoder().encode(strings)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw PersistenceError.corruptRow(table: databaseTableName, column: "turn_ids_json", value: nil)
        }
        return json
    }

    private static func decodeTurnIDs(_ json: String) throws -> [TranscriptTurnID] {
        guard let data = json.data(using: .utf8) else { return [] }
        let strings = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return strings.compactMap { UUID(uuidString: $0) }.map { TranscriptTurnID(rawValue: $0) }
    }
}

/// A raw embedding row scoped to an authorized meeting set, handed back to
/// `NSPIntelligence`'s `HybridRetriever` to score in Swift.
public struct EmbeddingCandidateRow: Sendable {
    public let meetingID: MeetingID
    public let turnIDs: [TranscriptTurnID]
    public let sampleStart: Int64
    public let sampleEnd: Int64
    public let chunkText: String
    public let vector: [Float]
}
