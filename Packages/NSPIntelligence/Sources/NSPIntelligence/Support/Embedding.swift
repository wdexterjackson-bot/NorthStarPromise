/// One vector produced by `EmbedderProtocol` (docs/04 §2). Validity is
/// scoped to the model that produced it — `EmbedderProtocol.modelIdentifier`
/// changing invalidates every existing `Embedding` (docs/04 §10.3).
public struct Embedding: Sendable, Hashable, Codable {
    public let vector: [Float]

    public init(vector: [Float]) {
        self.vector = vector
    }
}
