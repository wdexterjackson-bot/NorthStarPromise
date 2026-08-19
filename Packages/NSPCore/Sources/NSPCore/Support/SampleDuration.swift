/// A duration derived from a sample count at a known rate — never from wall
/// clock arithmetic (Invariant-adjacent rule in docs/03, "Timeline math").
public struct SampleDuration: Sendable, Hashable, Codable {
    public let sampleCount: Int64
    public let sampleRate: Int

    public init(sampleCount: Int64, sampleRate: Int) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        self.sampleCount = sampleCount
        self.sampleRate = sampleRate
    }

    public var seconds: Double { Double(sampleCount) / Double(sampleRate) }

    public static let zero = SampleDuration(sampleCount: 0, sampleRate: 1)
}
