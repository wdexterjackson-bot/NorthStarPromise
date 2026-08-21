import Foundation
import NSPCore
import Testing

@testable import NSPIntelligence

/// Real, enabled unit tests for the I4-enforcement half `EvidenceGrounder`
/// implements — narrower than `EvidenceCoverageTests`' still-`.disabled`
/// full-pipeline gate, but exercises the exact grounding logic that gate
/// will eventually run against fixture meetings.
@Suite("EvidenceGrounder")
struct EvidenceGrounderTests {
    private static let meetingID = MeetingID(rawValue: UUID())

    private static func makeTurn(text: String, startSample: Int64) -> TranscriptTurn {
        let words = text.split(separator: " ")
        var sample = startSample
        let tokens = words.map { word -> Token in
            let token = Token(text: String(word), startSample: sample, endSample: sample + 50, confidence: 0.9)
            sample += 60
            return token
        }
        return TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), owner: .meeting(meetingID), revision: 1, isProvisional: false,
            tokens: tokens, segmentRefs: [])
    }

    @Test func test_ground_exactQuoteInReferencedTurn_producesARealEvidenceSpan() {
        let turn = Self.makeTurn(text: "I will send the recap by Friday", startSample: 1000)

        let span = EvidenceGrounder.ground(
            turnIDs: [turn.turnID], quotedText: "send the recap by Friday", meetingID: Self.meetingID,
            transcriptRevision: 1, in: [turn])

        #expect(span != nil)
        #expect(span?.turnIDs == [turn.turnID])
        #expect(span?.sampleRange.startSample == turn.tokens.first?.startSample)
        #expect(span?.sampleRange.endSample == turn.tokens.last?.endSample)
    }

    @Test func test_ground_isCaseAndWhitespaceInsensitive() {
        let turn = Self.makeTurn(text: "We agreed to ship on Monday", startSample: 0)

        let span = EvidenceGrounder.ground(
            turnIDs: [turn.turnID], quotedText: "  SHIP   on monday  ", meetingID: Self.meetingID,
            transcriptRevision: 1, in: [turn])

        #expect(span != nil)
    }

    @Test func test_ground_quoteNotActuallySaid_dropsTheClaim() {
        let turn = Self.makeTurn(text: "We agreed to ship on Monday", startSample: 0)

        let span = EvidenceGrounder.ground(
            turnIDs: [turn.turnID], quotedText: "we will double the budget", meetingID: Self.meetingID,
            transcriptRevision: 1, in: [turn])

        #expect(span == nil)
    }

    @Test func test_ground_referencedTurnNotInTranscript_dropsTheClaim() {
        let realTurn = Self.makeTurn(text: "We agreed to ship on Monday", startSample: 0)
        let hallucinatedTurnID = TranscriptTurnID(rawValue: UUID())

        let span = EvidenceGrounder.ground(
            turnIDs: [hallucinatedTurnID], quotedText: "ship on Monday", meetingID: Self.meetingID,
            transcriptRevision: 1, in: [realTurn])

        #expect(span == nil)
    }

    @Test func test_ground_emptyTurnIDs_dropsTheClaim() {
        let turn = Self.makeTurn(text: "We agreed to ship on Monday", startSample: 0)

        let span = EvidenceGrounder.ground(
            turnIDs: [], quotedText: "ship on Monday", meetingID: Self.meetingID, transcriptRevision: 1, in: [turn])

        #expect(span == nil)
    }

    @Test func test_ground_quoteSpanningTwoReferencedTurns_spansBothTurnsSampleRange() {
        let first = Self.makeTurn(text: "We agreed to ship", startSample: 0)
        let second = Self.makeTurn(text: "the update on Monday", startSample: 10_000)

        let span = EvidenceGrounder.ground(
            turnIDs: [first.turnID, second.turnID], quotedText: "ship the update on Monday",
            meetingID: Self.meetingID, transcriptRevision: 1, in: [first, second])

        #expect(span != nil)
        #expect(span?.sampleRange.startSample == first.tokens.first?.startSample)
        #expect(span?.sampleRange.endSample == second.tokens.last?.endSample)
    }

    @Test func test_ground_emptyQuotedText_dropsTheClaim() {
        let turn = Self.makeTurn(text: "We agreed to ship on Monday", startSample: 0)

        let span = EvidenceGrounder.ground(
            turnIDs: [turn.turnID], quotedText: "   ", meetingID: Self.meetingID, transcriptRevision: 1, in: [turn])

        #expect(span == nil)
    }
}
