/// One diarized speaker grouping — "id, embedding centroid, total speech
/// samples" (docs/04 §2). `clusterID` is a plain `String`, not a
/// `TypedID<Tag>`, matching `DiarizationResult.assignments`'s own
/// `clusterID: String` field exactly.
public struct SpeakerCluster: Sendable, Hashable, Codable, Identifiable {
    public let clusterID: String
    public var id: String { clusterID }
    public let embeddingCentroid: [Float]
    public let totalSpeechSamples: Int64

    public init(clusterID: String, embeddingCentroid: [Float], totalSpeechSamples: Int64) {
        self.clusterID = clusterID
        self.embeddingCentroid = embeddingCentroid
        self.totalSpeechSamples = totalSpeechSamples
    }
}
