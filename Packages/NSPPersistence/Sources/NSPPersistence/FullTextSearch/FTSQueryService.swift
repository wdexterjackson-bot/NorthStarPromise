import Foundation
@preconcurrency import GRDB
import NSPCore

public enum FTSSource: String, Sendable, Hashable {
    case transcript
    case notes
    case insight
}

/// One FTS5 hit — `turnID`/`blockID`/`insightID` collapse to a single
/// `sourceRowID` string since the caller (`HybridRetriever`) only needs it
/// to resolve back to a `TranscriptTurnID` (via `fts_transcript`'s
/// `turn_id`) or to identify which note/insight matched; only transcript
/// hits currently feed the fused, turn-aligned chunk pipeline (docs/04
/// §10.3's citations are transcript turn ranges).
public struct FTSHit: Sendable, Hashable {
    public let source: FTSSource
    public let sourceRowID: String
    public let meetingID: MeetingID
    /// Lower is a better match (`bm25()`'s own convention — more negative
    /// is more relevant).
    public let bm25Rank: Double
}

/// Queries the FTS5 shells `Migration004`'s triggers keep populated.
/// Authorization-scoped: every query takes the already-resolved permitted
/// `meetingID` set and joins on it directly in SQL — there is no path here
/// that queries unscoped (docs/04 §10.2, docs/06 §5's hard rule).
public protocol FTSQueryService: Sendable {
    func search(query: String, meetingIDs: Set<MeetingID>, limit: Int) async throws -> [FTSHit]
}

public struct GRDBFTSQueryService: FTSQueryService {
    private let dbWriter: any DatabaseWriter

    /// A minimal stopword list — filtered out of the FTS query terms so
    /// "when is the Executive Report due" doesn't waste BM25 weight
    /// matching "when"/"is"/"the" against every transcript in the corpus.
    /// Deliberately small and hardcoded (not a glossary/NLU feature) — the
    /// real "understand the question" work happens in the answering LLM
    /// stage (docs/04 §10.4), not here; this is just noise reduction for
    /// the lexical half of retrieval.
    private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "he", "in", "is", "it", "its", "of",
        "on", "that", "the", "to", "was", "were", "will", "with", "when", "where", "which", "who", "what", "why",
        "how", "do", "does", "did", "can", "could", "would", "should",
    ]

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func search(query: String, meetingIDs: Set<MeetingID>, limit: Int) async throws -> [FTSHit] {
        guard !meetingIDs.isEmpty else { return [] }
        let matchQuery = Self.buildMatchQuery(query)
        guard !matchQuery.isEmpty else { return [] }
        let ids = meetingIDs.map { $0.rawValue.uuidString }

        return try await dbWriter.read { db in
            var hits: [FTSHit] = []
            hits += try Self.searchTable(
                db, Self.transcriptTable, matchQuery: matchQuery, meetingIDs: ids, limit: limit)
            hits += try Self.searchTable(db, Self.notesTable, matchQuery: matchQuery, meetingIDs: ids, limit: limit)
            hits += try Self.searchTable(db, Self.insightTable, matchQuery: matchQuery, meetingIDs: ids, limit: limit)
            return hits
        }
    }

    /// Groups a table's name, its row-identifier column, and which
    /// `FTSSource` it represents — collapses what would otherwise be three
    /// separate parameters on `searchTable` (SwiftLint's
    /// `function_parameter_count` caps at 5).
    private struct FTSTableSpec {
        let table: String
        let idColumn: String
        let source: FTSSource
    }

    private static let transcriptTable = FTSTableSpec(table: "fts_transcript", idColumn: "turn_id", source: .transcript)
    private static let notesTable = FTSTableSpec(table: "fts_notes", idColumn: "block_id", source: .notes)
    private static let insightTable = FTSTableSpec(table: "fts_insight", idColumn: "insight_id", source: .insight)

    private static func searchTable(
        _ db: Database, _ spec: FTSTableSpec, matchQuery: String, meetingIDs: [String], limit: Int
    ) throws -> [FTSHit] {
        let placeholders = meetingIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT \(spec.idColumn) AS row_id, meeting_id, bm25(\(spec.table)) AS rank
            FROM \(spec.table)
            WHERE \(spec.table) MATCH ? AND meeting_id IN (\(placeholders))
            ORDER BY rank
            LIMIT ?
            """
        var arguments: [DatabaseValueConvertible] = [matchQuery]
        arguments.append(contentsOf: meetingIDs)
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        return try rows.map { row in
            let meetingIDString: String = row["meeting_id"]
            guard let meetingUUID = UUID(uuidString: meetingIDString) else {
                throw PersistenceError.corruptRow(table: spec.table, column: "meeting_id", value: meetingIDString)
            }
            return FTSHit(
                source: spec.source, sourceRowID: row["row_id"], meetingID: MeetingID(rawValue: meetingUUID),
                bm25Rank: row["rank"])
        }
    }

    /// Builds an FTS5 `MATCH` expression that ORs together every
    /// non-stopword term, each individually double-quoted so punctuation in
    /// a real question (`"due?"`, `"Report,"`) can never be misread as FTS5
    /// query syntax — every term is a literal string match, not a
    /// phrase/prefix/boolean operator.
    private static func buildMatchQuery(_ text: String) -> String {
        let words =
            text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !Self.stopwords.contains($0) }
        guard !words.isEmpty else { return "" }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}
