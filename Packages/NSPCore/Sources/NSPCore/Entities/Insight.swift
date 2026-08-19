import Foundation

/// Where a generated row came from — required on every generated row
/// (docs/02 §1 principle 5).
public struct Provenance: Sendable, Hashable, Codable {
    public let modelID: String
    public let modelVersion: String
    public let promptVersion: String
    public let templateID: String?
    public let templateVersion: String?
    public let generatedAt: Date
    public let processingPlane: ProcessingPlane

    public init(
        modelID: String,
        modelVersion: String,
        promptVersion: String,
        templateID: String? = nil,
        templateVersion: String? = nil,
        generatedAt: Date,
        processingPlane: ProcessingPlane
    ) {
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.promptVersion = promptVersion
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.generatedAt = generatedAt
        self.processingPlane = processingPlane
    }
}

/// Which processing ladder rung produced a `Provenance` (docs/04 § processing
/// ladder). Content-bearing generation is either fully on-device or ran
/// against a `ProcessingGrant`-gated cloud call — never ambiguous.
public enum ProcessingPlane: String, Sendable, Hashable, Codable, CaseIterable {
    case onDevice
    case cloud
}

/// One generated summary/decision/action/risk bullet (docs/02 §2). Empty
/// `evidence` forces `claimKind == .aiSuggests` (Invariant I4) — that
/// constraint is enforced by `NSPIntelligence`, not representable-away here
/// since the generator, not the type, is what can violate it.
public struct Insight: Sendable, Hashable, Codable, Identifiable {
    public let insightID: InsightID
    public var id: InsightID { insightID }
    public let meetingID: MeetingID

    public let layer: InsightLayer
    public var text: String
    public let claimKind: ClaimKind
    public let evidence: [EvidenceSpan]
    public let confidence: Double
    public let provenance: Provenance
    public var approvalState: ApprovalState
    public let supersedes: InsightID?

    public init(
        insightID: InsightID,
        meetingID: MeetingID,
        layer: InsightLayer,
        text: String,
        claimKind: ClaimKind,
        evidence: [EvidenceSpan],
        confidence: Double,
        provenance: Provenance,
        approvalState: ApprovalState = .draft,
        supersedes: InsightID? = nil
    ) {
        self.insightID = insightID
        self.meetingID = meetingID
        self.layer = layer
        self.text = text
        self.claimKind = claimKind
        self.evidence = evidence
        self.confidence = confidence
        self.provenance = provenance
        self.approvalState = approvalState
        self.supersedes = supersedes
    }
}
