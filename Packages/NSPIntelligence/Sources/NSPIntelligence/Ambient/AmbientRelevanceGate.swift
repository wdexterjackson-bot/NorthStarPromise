import Foundation
import NSPCore

/// One short window of ambient speech — the unit `AmbientCoordinator`'s
/// rolling buffer hands to the relevance gate. Never persisted on its own;
/// it either gets discarded or becomes the `excerpt` inside an
/// `AmbientEvidence` the moment a suggestion is created ("Overheard"
/// recommendation, 2026-08-22).
public struct AmbientWindow: Sendable, Equatable {
    public let text: String
    public let capturedAt: Date

    public init(text: String, capturedAt: Date) {
        self.text = text
        self.capturedAt = capturedAt
    }
}

/// Decides whether a window is worth the cost of full extraction — the
/// difference between a battery-reasonable feature and a battery-hostile
/// one, since almost everything said while Ambient Mode is on should be
/// discarded before anything expensive runs.
public protocol AmbientRelevanceGating: Sendable {
    func isRelevant(_ window: AmbientWindow) -> Bool
}

/// A deterministic, on-device, fully unit-testable relevance gate —
/// requires a *positive* signal (commitment language, a self-directed
/// reminder, an explicit decision, or a scheduling confirmation) rather
/// than trying to enumerate every irrelevant pattern, since a denylist
/// approach can never be complete. Deliberately excludes bare requests
/// ("can you pass the salt") — those match no positive category here,
/// which is the point: a real command that happens to start with "could
/// you" still needs a *task-shaped* signal to fire, not politeness alone.
///
/// This is a heuristic, not a language model — it will both miss things
/// and occasionally fire on something harmless. That's an acceptable
/// trade for v1 given nothing it produces is ever auto-added (every
/// suggestion waits for a human in the Ambient Suggestions inbox); a
/// FoundationModels-backed classifier is the natural upgrade once that can
/// be verified on real hardware, which this environment can't do.
public struct HeuristicAmbientRelevanceGate: AmbientRelevanceGating {
    /// Below this word count, even a matched phrase is usually a fragment
    /// ("I'll—" cut off mid-sentence) rather than a complete thought worth
    /// surfacing.
    private static let minimumWordCount = 4

    private static let commitmentPhrases = [
        "i'll ", "i will ", "i'm going to ", "i am going to ", "i'll be ", "i will be ",
    ]
    private static let selfReminderPhrases = [
        "remind me to", "don't forget to", "i need to", "i still need to", "i've got to", "i have to",
    ]
    fileprivate static let decisionPhrases = [
        "we decided", "we agreed", "we're going with", "we are going with", "the decision is", "let's go with",
        "settled on",
    ]
    private static let confirmationPhrases = [
        "works", "sounds good", "perfect", "confirmed", "see you then", "i'll be there", "that works",
    ]
    private static let weekdayNames = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tomorrow", "tonight",
    ]

    public init() {}

    public func isRelevant(_ window: AmbientWindow) -> Bool {
        let text = window.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let wordCount = text.split(separator: " ").count
        guard wordCount >= Self.minimumWordCount else { return false }

        if Self.containsAny(of: Self.commitmentPhrases, in: text) { return true }
        if Self.containsAny(of: Self.selfReminderPhrases, in: text) { return true }
        if Self.containsAny(of: Self.decisionPhrases, in: text) { return true }
        if Self.containsAny(of: Self.weekdayNames, in: text), Self.containsAny(of: Self.confirmationPhrases, in: text)
        {
            return true
        }
        return false
    }

    fileprivate static func containsAny(of phrases: [String], in text: String) -> Bool {
        phrases.contains { text.range(of: $0, options: [.caseInsensitive]) != nil }
    }
}

/// What the relevance-gated window turned into, ready to become an
/// `AmbientSuggestion` — everything here is honest about coming from a
/// heuristic, not a model: `text` is the excerpt near-verbatim (never
/// fabricated or paraphrased), and `threadID`/`counterpartyID` are only
/// ever set from an actual name/title match, never guessed.
public struct AmbientExtractionResult: Sendable, Equatable {
    public let kind: AmbientSuggestionKind
    public let text: String
    public let threadID: NSPThreadID?
    public let counterpartyID: PersonID?

    public init(kind: AmbientSuggestionKind, text: String, threadID: NSPThreadID?, counterpartyID: PersonID?) {
        self.kind = kind
        self.text = text
        self.threadID = threadID
        self.counterpartyID = counterpartyID
    }
}

public protocol AmbientExtracting: Sendable {
    func extract(_ window: AmbientWindow, knownPeople: [Person], knownThreads: [NSPThread]) -> AmbientExtractionResult
}

/// Same "no model, fully testable" reasoning as `HeuristicAmbientRelevanceGate`
/// — a window that already passed the relevance gate is turned into a
/// suggestion by simple substring matching against known People/Threads,
/// never invented. A person who opted out (`Person.ambientListeningOptOut`)
/// is excluded from matching entirely, so a suggestion is never attributed
/// to them even coarsely.
public struct HeuristicAmbientExtractor: AmbientExtracting {
    public init() {}

    public func extract(
        _ window: AmbientWindow, knownPeople: [Person], knownThreads: [NSPThread]
    ) -> AmbientExtractionResult {
        let text = window.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: AmbientSuggestionKind =
            HeuristicAmbientRelevanceGate.containsAny(of: HeuristicAmbientRelevanceGate.decisionPhrases, in: text)
            ? .decision : .action

        let matchedPerson = knownPeople.first { person in
            guard !person.ambientListeningOptOut else { return false }
            let candidates = [person.name] + person.aliases
            return candidates.contains { !$0.isEmpty && text.range(of: $0, options: [.caseInsensitive]) != nil }
        }
        let matchedThread = knownThreads.first { thread in
            !thread.title.isEmpty && text.range(of: thread.title, options: [.caseInsensitive]) != nil
        }

        return AmbientExtractionResult(
            kind: kind, text: text, threadID: matchedThread?.threadID, counterpartyID: matchedPerson?.personID)
    }
}
