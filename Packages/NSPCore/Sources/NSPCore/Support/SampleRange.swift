/// An inclusive-start, exclusive-end span on a meeting's canonical sample
/// timeline. The only ordering primitive timeline math and evidence anchors
/// are allowed to use (docs/03, "Timeline math").
public struct SampleRange: Sendable, Hashable, Codable {
    public let startSample: Int64
    public let endSample: Int64

    public init(startSample: Int64, endSample: Int64) {
        precondition(endSample >= startSample, "SampleRange end must not precede start")
        self.startSample = startSample
        self.endSample = endSample
    }

    public var sampleCount: Int64 { endSample - startSample }
}
