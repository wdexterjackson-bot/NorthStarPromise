import NSPCore
import NSPIntelligence
import Observation

/// Where one Ask session's last query landed. `.failed` covers both a
/// thrown authorization/retrieval error and `AskAnswer.refusalReason` —
/// `AskView` doesn't need to distinguish "no model" from "nothing found,"
/// both read as "here's why there's no answer."
public enum AskState: Equatable {
    case idle
    case asking
    case answered(AskAnswer.Snapshot)
    case failed(String)
}

/// Thin App-layer orchestrator over `NSPIntelligence`'s Ask primitives —
/// same shape as `IntelligenceCoordinator`/`ScheduledRecordingCoordinator`:
/// composition only. Builds a fresh `HybridRetriever` per question rather
/// than once at `AppEnvironment.init()` time, because a `HybridRetriever`
/// needs a concrete `WorkspaceID` and `AppEnvironment.defaultPolicy` isn't
/// set until `bootstrap()` completes, well after `AppEnvironment.init()`
/// returns — the same reason `RecordingSession` is constructed by the view
/// layer instead of `AppEnvironment` itself.
@MainActor
@Observable
public final class AskCoordinator {
    public private(set) var state: AskState = .idle

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func ask(_ question: String, scope: AskScope) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        state = .asking

        let retriever = HybridRetriever(
            ftsQueryService: environment.ftsQueryService, embedder: environment.embedder,
            embeddingRepository: environment.embeddingRepository,
            transcriptTurnRepository: environment.transcriptTurnRepository,
            authorizationResolver: environment.askAuthorizationResolver, currentWorkspaceID: workspaceID)

        do {
            let chunks = try await retriever.retrieve(RetrievalQuery(text: trimmed), scope: scope)
            let answer = try await environment.askAnswerer.answer(question: trimmed, chunks: chunks)
            if let refusalReason = answer.refusalReason {
                state = .failed(refusalReason)
            } else {
                state = .answered(AskAnswer.Snapshot(text: answer.text, citations: answer.citations))
            }
        } catch {
            state = .failed("\(error)")
        }
    }

    public func reset() {
        state = .idle
    }
}

extension AskAnswer {
    /// `AskAnswer` itself doesn't conform to `Equatable` (no need to, until
    /// now) — this is the small, `Equatable` subset `AskState` needs to
    /// support SwiftUI's `.animation(value:)`/`onChange` idioms.
    public struct Snapshot: Equatable {
        public let text: String
        public let citations: [Citation]
    }
}
