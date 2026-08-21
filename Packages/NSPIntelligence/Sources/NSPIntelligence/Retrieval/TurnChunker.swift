import NSPCore

/// One turn-aligned chunk with overlap (docs/04 §10.3: "chunks are
/// turn-aligned with overlap so a citation is always a real turn range").
public struct ChunkWindow: Sendable, Hashable {
    public let turnIDs: [TranscriptTurnID]
    public let text: String
    public let sampleRange: SampleRange
}

/// The single source of truth for chunk boundaries — used both when
/// writing embeddings (`EmbeddingIndexer`) and when expanding a raw FTS
/// turn-hit into a comparable chunk for fusion (`HybridRetriever`), so FTS
/// and vector results can dedupe on identical `(meetingID, turnIDs)` keys
/// rather than double-counting overlapping content as two separate results.
public enum TurnChunker {
    /// Sliding window over a meeting's turns, already ordered by start
    /// sample (`TranscriptTurnRepository.fetchAll`'s own contract).
    /// `windowSize: 3, stride: 2` gives a one-turn overlap between
    /// consecutive windows.
    public static func windows(for turns: [TranscriptTurn], windowSize: Int = 3, stride: Int = 2) -> [ChunkWindow] {
        guard !turns.isEmpty, windowSize > 0, stride > 0 else { return [] }

        var result: [ChunkWindow] = []
        var start = 0
        while start < turns.count {
            let end = min(start + windowSize, turns.count)
            let windowTurns = Array(turns[start..<end])
            if let window = Self.makeWindow(from: windowTurns) {
                result.append(window)
            }
            if end == turns.count { break }
            start += stride
        }
        return result
    }

    /// Finds the window (from a fresh `windows(for:)` call over the same
    /// turns) that contains `turnID` — used by `HybridRetriever` to map a
    /// raw FTS turn-hit onto the same chunk boundaries the vector index
    /// already uses, so the two can fuse instead of double-counting.
    public static func enclosingWindow(for turnID: TranscriptTurnID, in turns: [TranscriptTurn]) -> ChunkWindow? {
        Self.windows(for: turns).first { $0.turnIDs.contains(turnID) }
    }

    private static func makeWindow(from turns: [TranscriptTurn]) -> ChunkWindow? {
        guard !turns.isEmpty else { return nil }
        let text = turns.map { turn in turn.tokens.map(\.text).joined(separator: " ") }.joined(separator: " ")
        let starts = turns.compactMap { $0.tokens.first?.startSample }
        let ends = turns.compactMap { $0.tokens.last?.endSample }
        guard let start = starts.min(), let end = ends.max(), end >= start else { return nil }
        return ChunkWindow(
            turnIDs: turns.map(\.turnID), text: text, sampleRange: SampleRange(startSample: start, endSample: end))
    }
}
