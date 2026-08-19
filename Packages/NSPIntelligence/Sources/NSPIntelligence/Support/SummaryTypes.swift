import NSPCore

/// How strictly a template requires evidence spans to be exact quotes
/// (docs/04 §6). `legalDepositionSupport` forces `.verbatim`.
public enum EvidenceStrictness: String, Sendable, Hashable, Codable, CaseIterable {
    case standard
    case verbatim
}

/// The shipped template library (docs/04 §6, verbatim names). Custom
/// templates clone one of these and are workspace-scoped — represented by
/// `SummaryTemplate.templateID` being any other string, not a case here.
public enum ShippedSummaryTemplate: String, Sendable, Hashable, Codable, CaseIterable {
    case oneOnOne
    case standup
    case board
    case projectReview
    case salesDiscovery
    case interview
    case regulatedRecord
    case lecture
    case brainstorm
    case retrospective
    case legalDepositionSupport
}

/// A versioned, `Codable` value (docs/04 §6, verbatim): section list,
/// per-section prompt fragment, required layers, required fields, tone
/// defaults, and an evidence-strictness level. Rendering the prompt itself
/// — the fenced-nonce data channel, `UntrustedText` — is `PromptBuilder`'s
/// job and lands with NSP-088; this type only carries the template's own
/// declared shape.
public struct SummaryTemplate: Sendable, Hashable, Codable, Identifiable {
    public let templateID: String
    public var id: String { templateID }
    public let templateVersion: String
    public let sections: [String]
    public let sectionPromptFragments: [String: String]
    public let requiredLayers: Set<InsightLayer>
    public let requiredFields: [String]
    public let toneDefault: SummaryTone
    public let evidenceStrictness: EvidenceStrictness
    /// `legalDepositionSupport` ships this `true` — "not legal advice,"
    /// disclosed in template metadata and every export header (docs/04 §6).
    public let requiresLegalDisclaimer: Bool

    public init(
        templateID: String, templateVersion: String, sections: [String],
        sectionPromptFragments: [String: String], requiredLayers: Set<InsightLayer>, requiredFields: [String],
        toneDefault: SummaryTone, evidenceStrictness: EvidenceStrictness, requiresLegalDisclaimer: Bool = false
    ) {
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.sections = sections
        self.sectionPromptFragments = sectionPromptFragments
        self.requiredLayers = requiredLayers
        self.requiredFields = requiredFields
        self.toneDefault = toneDefault
        self.evidenceStrictness = evidenceStrictness
        self.requiresLegalDisclaimer = requiresLegalDisclaimer
    }
}

public enum SummaryLength: String, Sendable, Hashable, Codable, CaseIterable {
    case brief
    case standard
    case detailed
}

public enum SummaryTone: String, Sendable, Hashable, Codable, CaseIterable {
    case neutral
    case formal
    case casual
}

public enum SummaryAudience: String, Sendable, Hashable, Codable, CaseIterable {
    case internalTeam
    case external
    case executive
}

/// The untrusted transcript payload a `SummarizerProtocol` call carries
/// (docs/04 §2's `SummarizationRequest.transcript`, docs/04 §7's "untrusted
/// data channel payload"). This type only carries the turns; the structural
/// enforcement that content can never enter a privileged instruction region
/// — nonce-fenced rendering, the `UntrustedText` wrapper, `PromptBuilder` —
/// is Invariant I7's full mechanism and lands with NSP-088
/// (`PromptInjectionTests.swift`, currently `.disabled` pending it).
public struct TranscriptWindow: Sendable, Hashable {
    public let meetingID: MeetingID
    public let turns: [TranscriptTurn]

    public init(meetingID: MeetingID, turns: [TranscriptTurn]) {
        self.meetingID = meetingID
        self.turns = turns
    }
}

/// One proposed layered-output row, pre-validation (docs/04 §2
/// `SummarizationResult.insights`). Becomes an `Insight` only after the
/// evidence resolver / entailment checker ladder (docs/04 §4.2, NSP-044,
/// NSP-046) — a `DraftInsight` is not yet trusted.
public struct DraftInsight: Sendable, Hashable {
    public let layer: InsightLayer
    public var text: String
    public let claimKind: ClaimKind
    public let evidence: [EvidenceSpan]
    public let confidence: Double

    public init(layer: InsightLayer, text: String, claimKind: ClaimKind, evidence: [EvidenceSpan], confidence: Double) {
        self.layer = layer
        self.text = text
        self.claimKind = claimKind
        self.evidence = evidence
        self.confidence = confidence
    }
}

/// Why a summarizer declined a section outright — surfaced, never hidden
/// (docs/04 §2 `SummarizationResult.refusals`).
public enum RefusalReason: Sendable, Hashable {
    case insufficientEvidence(section: String)
    case contentPolicyDeclined(section: String)
    case modelUnavailable
}
