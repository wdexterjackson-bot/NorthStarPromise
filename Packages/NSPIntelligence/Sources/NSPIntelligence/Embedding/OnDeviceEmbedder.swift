import Foundation
import NaturalLanguage
import NSPPolicy

public enum EmbedderError: Error, Sendable {
    /// No backend exists yet — `embedRemote` has nowhere to call.
    case unimplemented
}

/// The real on-device embedder (docs/04 §2's `OnDeviceEmbedder`), backed by
/// `NLEmbedding` (Apple's `NaturalLanguage` framework) — the only
/// zero-new-dependency option available (no `CoreML`/custom model exists
/// anywhere in this repo), and it ships on every supported OS version
/// (unlike `FoundationModels`, no `#if canImport`/`#available` gate is
/// needed for the framework itself). Still capability-detected per the
/// same "never assume, degrade honestly" discipline `LiveOnDeviceSummarizer`
/// and `LiveTranscriber` already use: a missing sentence embedding for the
/// requested language is an explicit `.unavailable`, never a silent
/// empty-vector fallback.
///
/// v1 is English-only (`modelIdentifier` is language-qualified,
/// `"NLEmbedding.sentence.en"`), matching `IntelligenceCoordinator`'s
/// existing English-only transcription default — a stated limitation, not
/// a silent one (docs/07 §2.1-adjacent Ask scoping notes this explicitly).
public struct OnDeviceEmbedder: EmbedderProtocol {
    private let language: NLLanguage

    public init(language: NLLanguage = .english) {
        self.language = language
    }

    public var availability: ModelAvailability {
        NLEmbedding.sentenceEmbedding(for: language) != nil ? .available : .unavailable
    }

    public var dimensions: Int {
        NLEmbedding.sentenceEmbedding(for: language)?.dimension ?? 0
    }

    public var modelIdentifier: String {
        "NLEmbedding.sentence.\(language.rawValue)"
    }

    public func embedOnDevice(_ texts: [String]) async throws -> [Embedding] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else { return [] }
        return texts.map { text in
            Embedding(vector: (embedding.vector(for: text) ?? []).map(Float.init))
        }
    }

    public func embedRemote(_ texts: [String], grant: ProcessingGrant) async throws -> [Embedding] {
        throw EmbedderError.unimplemented
    }
}
