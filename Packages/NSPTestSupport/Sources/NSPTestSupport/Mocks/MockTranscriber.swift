import Foundation
import NSPIntelligence
import NSPPolicy

/// Thrown by `MockTranscriber` when constructed with `shouldDrop: true` —
/// simulates a transcription attempt that never returns (docs/04 §2.1).
public struct MockTranscriberDroppedError: Error, Sendable, Hashable {}

/// Replays a fixed `TranscriptionResult` with injectable latency and drop
/// behavior (docs/04 §2.1). The result's own `meanConfidence` is the
/// "confidence profile" — construct different fixtures to exercise
/// low-confidence handling.
public actor MockTranscriber: TranscriberProtocol {
    public nonisolated let capabilities: TranscriberCapabilities

    private let fixtureResult: TranscriptionResult
    private let latencyNanoseconds: UInt64
    private let shouldDrop: Bool

    public init(
        fixtureResult: TranscriptionResult, latencyNanoseconds: UInt64 = 0, shouldDrop: Bool = false,
        capabilities: TranscriberCapabilities = TranscriberCapabilities(
            supportedLanguages: [Locale.Language(identifier: "en")], supportsWordTimings: true,
            supportsStreaming: true, availability: .available)
    ) {
        self.fixtureResult = fixtureResult
        self.latencyNanoseconds = latencyNanoseconds
        self.shouldDrop = shouldDrop
        self.capabilities = capabilities
    }

    public func transcribeOnDevice(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try await simulateLatencyAndDrop()
        return fixtureResult
    }

    public func transcribeRemote(
        _ request: TranscriptionRequest, grant: ProcessingGrant
    ) async throws -> TranscriptionResult {
        try await transcribeOnDevice(request)
    }

    public nonisolated func streamOnDevice(_ request: StreamRequest) -> AsyncThrowingStream<PartialTranscript, Error> {
        makeStream()
    }

    public nonisolated func streamRemote(_ request: StreamRequest, grant: ProcessingGrant) -> AsyncThrowingStream<
        PartialTranscript, Error
    > {
        makeStream()
    }

    private func simulateLatencyAndDrop() async throws {
        if latencyNanoseconds > 0 {
            try await Task.sleep(nanoseconds: latencyNanoseconds)
        }
        if shouldDrop {
            throw MockTranscriberDroppedError()
        }
    }

    private nonisolated func makeStream() -> AsyncThrowingStream<PartialTranscript, Error> {
        AsyncThrowingStream { continuation in
            for turn in fixtureResult.turns {
                let text = turn.tokens.map(\.text).joined(separator: " ")
                continuation.yield(
                    PartialTranscript(
                        text: text, isFinal: true,
                        sampleOffset: turn.tokens.first?.startSample ?? 0))
            }
            continuation.finish()
        }
    }
}
