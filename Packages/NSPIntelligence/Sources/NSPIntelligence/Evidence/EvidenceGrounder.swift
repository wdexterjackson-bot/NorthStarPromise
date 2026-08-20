import Foundation
import NSPCore

/// The real, code-level enforcement of Invariant I4 ("every generated claim
/// carries evidence... claims that cannot be grounded are labelled
/// `suggestion`, never `decision`") that today exists only as a doc comment
/// on `Insight`/`Action`/`Decision`. Given a model's claimed
/// `(turnIDs, quotedText)` pair and the real transcript it was generated
/// from, verifies the claim is actually grounded before it becomes a real
/// `EvidenceSpan` — a claim referencing a turn that doesn't exist, or
/// quoting words the transcript never said, is dropped, never kept.
///
/// Deliberately not the full ML `EntailmentChecker` ladder docs/04 §4.2
/// describes (semantic entailment, not just lexical grounding) — that's a
/// documented follow-up (`NOT-002`... `NSP-046`), not this pass's scope.
/// This is the narrower, structural half: *did the model quote something
/// that's actually there*, which is fully deterministic and needs no model
/// of its own to check.
public enum EvidenceGrounder {
    /// `nil` if the claim doesn't ground: a referenced turn is missing from
    /// `turns`, or `quotedText` isn't actually present (case/whitespace/
    /// diacritic-insensitive) in the combined text of the turns it claims
    /// to come from.
    public static func ground(
        turnIDs: [TranscriptTurnID], quotedText: String, meetingID: MeetingID, transcriptRevision: Int,
        in turns: [TranscriptTurn]
    ) -> EvidenceSpan? {
        guard !turnIDs.isEmpty else { return nil }
        let turnsByID = Dictionary(uniqueKeysWithValues: turns.map { ($0.turnID, $0) })
        let matchedTurns = turnIDs.compactMap { turnsByID[$0] }
        guard matchedTurns.count == turnIDs.count else { return nil }

        let combinedText = matchedTurns.map { $0.tokens.map(\.text).joined(separator: " ") }.joined(separator: " ")
        guard Self.normalizedContains(haystack: combinedText, needle: quotedText) else { return nil }

        let starts = matchedTurns.compactMap { $0.tokens.first?.startSample }
        let ends = matchedTurns.compactMap { $0.tokens.last?.endSample }
        guard let start = starts.min(), let end = ends.max(), end >= start else { return nil }

        return EvidenceSpan(
            meetingID: meetingID, turnIDs: turnIDs, sampleRange: SampleRange(startSample: start, endSample: end),
            quotedText: quotedText, transcriptRevision: transcriptRevision)
    }

    private static func normalizedContains(haystack: String, needle: String) -> Bool {
        let normalizedNeedle = Self.normalize(needle)
        guard !normalizedNeedle.isEmpty else { return false }
        return Self.normalize(haystack).contains(normalizedNeedle)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
