import NSPIntelligence
import NSPPolicy

/// A seedable, deterministic PRNG — `Hasher`'s seed is randomized per
/// process (documented Swift behavior), so it can't back a fixture that
/// must produce the same vectors on every test run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// Hash-based deterministic vectors (docs/04 §2.1) — the same input text
/// always produces the same `Embedding`, with no external model dependency.
public actor MockEmbedder: EmbedderProtocol {
    public nonisolated let dimensions: Int
    public nonisolated let modelIdentifier: String
    public nonisolated let availability: ModelAvailability = .available

    public init(dimensions: Int = 8, modelIdentifier: String = "mock-embedder-v1") {
        self.dimensions = dimensions
        self.modelIdentifier = modelIdentifier
    }

    public func embedOnDevice(_ texts: [String]) async throws -> [Embedding] {
        texts.map { Self.deterministicEmbedding(for: $0, dimensions: dimensions) }
    }

    public func embedRemote(_ texts: [String], grant: ProcessingGrant) async throws -> [Embedding] {
        try await embedOnDevice(texts)
    }

    private static func deterministicEmbedding(for text: String, dimensions: Int) -> Embedding {
        var generator = SplitMix64(seed: fnv1aHash(text))
        let vector = (0..<dimensions).map { _ in Float.random(in: -1...1, using: &generator) }
        return Embedding(vector: vector)
    }

    private static func fnv1aHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
