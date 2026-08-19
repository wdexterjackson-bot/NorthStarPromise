import Foundation
import NSPCore
import NSPIntelligence
import NSPPolicy

/// Canned insights, including one deliberately ungrounded claim — non-empty
/// text, `claimKind != .aiSuggests`, but zero evidence spans — so the
/// evidence-coverage gate (Invariant I4, NSP-044…046) has a fixture that
/// exercises "must catch this" (docs/04 §2.1, §4). This mock does not
/// enforce I4 itself; it only supplies the fixture that later validation
/// is tested against.
public actor MockSummarizer: SummarizerProtocol {
    public nonisolated let availability: ModelAvailability

    private let cannedResult: SummarizationResult

    public init(availability: ModelAvailability = .available, cannedResult: SummarizationResult? = nil) {
        self.availability = availability
        self.cannedResult = cannedResult ?? Self.defaultCannedResult(meetingID: MeetingID(rawValue: UUID()))
    }

    public func summarizeOnDevice(_ request: SummarizationRequest) async throws -> SummarizationResult {
        cannedResult
    }

    public func summarizeRemote(
        _ request: SummarizationRequest, grant: ProcessingGrant
    ) async throws -> SummarizationResult {
        cannedResult
    }

    public static func defaultCannedResult(meetingID: MeetingID) -> SummarizationResult {
        let provenance = Provenance(
            modelID: "mock-summarizer", modelVersion: "1.0", promptVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 0), processingPlane: .onDevice)

        let grounded = DraftInsight(
            layer: .flashRecap, text: "The team agreed to ship Thursday.", claimKind: .agreed,
            evidence: [
                EvidenceSpan(
                    meetingID: meetingID, turnIDs: [TranscriptTurnID(rawValue: UUID())],
                    sampleRange: SampleRange(startSample: 0, endSample: 1000),
                    quotedText: "let's ship Thursday if QA signs off", transcriptRevision: 1)
            ], confidence: 0.9)

        let ungrounded = DraftInsight(
            layer: .flashRecap, text: "Someone promised a full refund to every customer.", claimKind: .said,
            evidence: [], confidence: 0.4)

        return SummarizationResult(insights: [grounded, ungrounded], provenance: provenance)
    }
}
