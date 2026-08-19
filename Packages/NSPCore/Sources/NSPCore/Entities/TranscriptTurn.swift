/// One word, with its own timing, confidence, and language — mandatory for
/// tap-to-audio, evidence links, and redaction (docs/02 §2).
public struct Token: Sendable, Hashable, Codable {
    public let text: String
    public let startSample: Int64
    public let endSample: Int64
    public let confidence: Double
    public let languageTag: String?

    public init(
        text: String, startSample: Int64, endSample: Int64, confidence: Double,
        languageTag: String? = nil
    ) {
        self.text = text
        self.startSample = startSample
        self.endSample = endSample
        self.confidence = confidence
        self.languageTag = languageTag
    }
}

/// A run of one language within a bilingual turn; the original-language span
/// survives even after a separate translation view is added (docs/02 §2).
public struct LanguageSpan: Sendable, Hashable, Codable {
    public let languageTag: String
    public let range: SampleRange

    public init(languageTag: String, range: SampleRange) {
        self.languageTag = languageTag
        self.range = range
    }
}

/// One speaker turn (docs/02 §2). Provisional revisions are negative;
/// canonical revisions start at 1 — a later revision never overwrites an
/// earlier one in place.
public struct TranscriptTurn: Sendable, Hashable, Codable, Identifiable {
    public let turnID: TranscriptTurnID
    public var id: TranscriptTurnID { turnID }
    public let meetingID: MeetingID

    public let revision: Int
    public let isProvisional: Bool
    public var speakerClusterID: String?
    /// Resolved identity. Never inferred without evidence.
    public var personID: PersonID?

    public let tokens: [Token]
    public let languageSpans: [LanguageSpan]
    public let segmentRefs: [SegmentID]
    public var editState: EditState

    public init(
        turnID: TranscriptTurnID,
        meetingID: MeetingID,
        revision: Int,
        isProvisional: Bool,
        speakerClusterID: String? = nil,
        personID: PersonID? = nil,
        tokens: [Token],
        languageSpans: [LanguageSpan] = [],
        segmentRefs: [SegmentID],
        editState: EditState = .machine
    ) {
        self.turnID = turnID
        self.meetingID = meetingID
        self.revision = revision
        self.isProvisional = isProvisional
        self.speakerClusterID = speakerClusterID
        self.personID = personID
        self.tokens = tokens
        self.languageSpans = languageSpans
        self.segmentRefs = segmentRefs
        self.editState = editState
    }
}
