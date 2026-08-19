import Foundation
import NSPCore
import NSPPolicy

/// docs/04 §2, verbatim.
public struct SummarizationRequest: Sendable {
    public let meetingID: MeetingID
    public let transcript: TranscriptWindow
    public let template: SummaryTemplate
    public let layers: Set<InsightLayer>
    /// Approved/locked blocks, passed as read-only context — regenerating
    /// them byte-differently is a bug (docs/04 §6).
    public let lockedInsights: [Insight]
    public let length: SummaryLength
    public let tone: SummaryTone
    public let audience: SummaryAudience
    public let outputLanguages: [Locale.Language]

    public init(
        meetingID: MeetingID, transcript: TranscriptWindow, template: SummaryTemplate, layers: Set<InsightLayer>,
        lockedInsights: [Insight] = [], length: SummaryLength, tone: SummaryTone, audience: SummaryAudience,
        outputLanguages: [Locale.Language]
    ) {
        self.meetingID = meetingID
        self.transcript = transcript
        self.template = template
        self.layers = layers
        self.lockedInsights = lockedInsights
        self.length = length
        self.tone = tone
        self.audience = audience
        self.outputLanguages = outputLanguages
    }
}

public struct SummarizationResult: Sendable {
    public let insights: [DraftInsight]
    public let provenance: Provenance
    public let refusals: [RefusalReason]

    public init(insights: [DraftInsight], provenance: Provenance, refusals: [RefusalReason] = []) {
        self.insights = insights
        self.provenance = provenance
        self.refusals = refusals
    }
}

/// docs/04 §2, verbatim. A missing on-device capability degrades to "no
/// summary" — never a silent fallback to `summarizeRemote` (Invariant I5,
/// docs/04 §2.1).
public protocol SummarizerProtocol: Sendable {
    func summarizeOnDevice(_ request: SummarizationRequest) async throws -> SummarizationResult
    func summarizeRemote(_ request: SummarizationRequest, grant: ProcessingGrant) async throws -> SummarizationResult
    var availability: ModelAvailability { get }
}
