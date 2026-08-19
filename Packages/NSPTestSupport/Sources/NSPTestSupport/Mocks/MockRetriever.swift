import NSPIntelligence
import NSPPolicy

/// Returns a fixed set of `RetrievedChunk`s regardless of query or scope
/// (docs/04 §2.1) — tests that need scope-sensitive behavior should assert
/// on what `scope` was passed, not rely on this mock filtering by it.
public actor MockRetriever: RetrieverProtocol {
    private let fixtureChunks: [RetrievedChunk]

    public init(fixtureChunks: [RetrievedChunk] = []) {
        self.fixtureChunks = fixtureChunks
    }

    public func retrieve(_ query: RetrievalQuery, scope: AskScope) async throws -> [RetrievedChunk] {
        fixtureChunks
    }

    public func retrieveRemote(
        _ query: RetrievalQuery, scope: AskScope, grant: ProcessingGrant
    ) async throws -> [RetrievedChunk] {
        fixtureChunks
    }
}
