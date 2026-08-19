import NSPPolicy

/// docs/04 §2, verbatim. `scope` is resolved to an authorization filter
/// *before* any index is touched (docs/04 §10.2) — there is no unscoped
/// entry point, on-device or remote.
public protocol RetrieverProtocol: Sendable {
    func retrieve(_ query: RetrievalQuery, scope: AskScope) async throws -> [RetrievedChunk]
    func retrieveRemote(_ query: RetrievalQuery, scope: AskScope, grant: ProcessingGrant) async throws
        -> [RetrievedChunk]
}
