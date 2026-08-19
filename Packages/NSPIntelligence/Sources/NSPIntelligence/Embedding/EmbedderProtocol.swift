import NSPPolicy

/// docs/04 §2, verbatim.
public protocol EmbedderProtocol: Sendable {
    func embedOnDevice(_ texts: [String]) async throws -> [Embedding]
    func embedRemote(_ texts: [String], grant: ProcessingGrant) async throws -> [Embedding]
    var dimensions: Int { get }
    /// Embeddings are invalid across model changes (docs/04 §10.3) — every
    /// consumer must key stored vectors by this string.
    var modelIdentifier: String { get }
}
