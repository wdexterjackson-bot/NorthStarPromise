import Foundation

/// A short verbatim text excerpt plus a timestamp — the honest alternative
/// to `EvidenceSpan` for Ambient Mode ("Overheard" recommendation,
/// 2026-08-22). `EvidenceSpan` requires a transcript turn range and an
/// audio time range (Invariant I4); Ambient Mode has neither — no audio
/// file, no stored transcript, only the rolling in-memory window that
/// triggered a suggestion. `AmbientEvidence` never gets confused with a
/// grounded meeting claim: the UI treatment for it always discloses "From
/// Ambient Mode — no recording exists."
public struct AmbientEvidence: Sendable, Hashable, Codable {
    public let excerpt: String
    public let capturedAt: Date

    public init(excerpt: String, capturedAt: Date) {
        self.excerpt = excerpt
        self.capturedAt = capturedAt
    }
}

/// What kind of real record a suggestion becomes once accepted.
public enum AmbientSuggestionKind: String, Sendable, Hashable, Codable, CaseIterable {
    case action
    case decision
}

/// `.pending` is the only state a suggestion is ever created in — nothing
/// in this pipeline auto-accepts (Invariant I6's spirit, extended to this
/// feature's own version of "the world changing").
public enum AmbientSuggestionStatus: String, Sendable, Hashable, Codable {
    case pending
    case accepted
    case rejected
}

/// One candidate item Ambient Mode's relevance gate + extraction pipeline
/// produced, waiting in the Ambient Suggestions inbox for a human decision.
/// Accepting one creates a real, freestanding `Action`/`Decision` with
/// `evidence: []` — the same "human directly asserted this, not an AI
/// extraction from a transcript" reasoning `ActionComposerView` already
/// uses for manually-created actions — never an `AmbientEvidence`-backed
/// claim presented as AI-grounded fact.
public struct AmbientSuggestion: Sendable, Hashable, Codable, Identifiable {
    public let ambientSuggestionID: AmbientSuggestionID
    public var id: AmbientSuggestionID { ambientSuggestionID }
    public let workspaceID: WorkspaceID

    public var kind: AmbientSuggestionKind
    public var text: String
    /// Set when the relevance/extraction pipeline matched this excerpt to
    /// a known Thread or Person — `nil` means "offered as a new Thread" or
    /// "no counterparty," the same fallback `AddAgendaItemFormView`'s
    /// project picker and `ActionComposerView`'s people picker already use.
    public var threadID: NSPThreadID?
    public var counterpartyID: PersonID?
    public var evidence: AmbientEvidence
    public var status: AmbientSuggestionStatus

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        ambientSuggestionID: AmbientSuggestionID,
        workspaceID: WorkspaceID,
        kind: AmbientSuggestionKind,
        text: String,
        threadID: NSPThreadID? = nil,
        counterpartyID: PersonID? = nil,
        evidence: AmbientEvidence,
        status: AmbientSuggestionStatus = .pending,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.ambientSuggestionID = ambientSuggestionID
        self.workspaceID = workspaceID
        self.kind = kind
        self.text = text
        self.threadID = threadID
        self.counterpartyID = counterpartyID
        self.evidence = evidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
