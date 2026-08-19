import NSPIntelligence
import NSPPolicy

/// Deterministic cluster assignment from a fixed fixture (docs/04 §2.1).
public actor MockDiarizer: DiarizerProtocol {
    private let fixtureResult: DiarizationResult

    public init(fixtureResult: DiarizationResult) {
        self.fixtureResult = fixtureResult
    }

    public func diarizeOnDevice(_ request: DiarizationRequest) async throws -> DiarizationResult {
        fixtureResult
    }

    public func diarizeRemote(
        _ request: DiarizationRequest, grant: ProcessingGrant
    ) async throws -> DiarizationResult {
        fixtureResult
    }
}
