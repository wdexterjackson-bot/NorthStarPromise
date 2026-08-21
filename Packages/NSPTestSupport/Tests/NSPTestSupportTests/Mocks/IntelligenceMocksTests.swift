import Foundation
import NSPCore
import NSPIntelligence
import Testing

@testable import NSPTestSupport

@Suite("NSP-040 — Intelligence protocol mocks")
struct IntelligenceMocksTests {
    @Test func test_mockTranscriber_replaysTheFixtureOnDeviceAndRemote() async throws {
        let meetingID = MeetingID(rawValue: UUID())
        let turn = TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), owner: .meeting(meetingID), revision: 1,
            isProvisional: false,
            tokens: [Token(text: "hello", startSample: 0, endSample: 100, confidence: 0.95)], segmentRefs: [])
        let fixture = TranscriptionResult(
            turns: [turn], languageSpans: [], meanConfidence: 0.95,
            provenance: Provenance(
                modelID: "m", modelVersion: "1", promptVersion: "1", generatedAt: Date(timeIntervalSince1970: 0),
                processingPlane: .onDevice))
        let transcriber = MockTranscriber(fixtureResult: fixture)
        let request = TranscriptionRequest(meetingID: meetingID, segments: [], expectedLanguages: [])

        let result = try await transcriber.transcribeOnDevice(request)
        #expect(result.turns == [turn])
    }

    @Test func test_mockTranscriber_shouldDrop_throws() async throws {
        let fixture = TranscriptionResult(
            turns: [], languageSpans: [], meanConfidence: 0,
            provenance: Provenance(
                modelID: "m", modelVersion: "1", promptVersion: "1", generatedAt: Date(timeIntervalSince1970: 0),
                processingPlane: .onDevice))
        let transcriber = MockTranscriber(fixtureResult: fixture, shouldDrop: true)
        let request = TranscriptionRequest(meetingID: MeetingID(rawValue: UUID()), segments: [], expectedLanguages: [])

        await #expect(throws: MockTranscriberDroppedError.self) {
            try await transcriber.transcribeOnDevice(request)
        }
    }

    @Test func test_mockDiarizer_returnsTheFixture() async throws {
        let fixtureResult = DiarizationResult(
            clusters: [SpeakerCluster(clusterID: "S1", embeddingCentroid: [0.1, 0.2], totalSpeechSamples: 1000)],
            assignments: [])
        let diarizer = MockDiarizer(fixtureResult: fixtureResult)
        let request = DiarizationRequest(meetingID: MeetingID(rawValue: UUID()), segments: [])

        let result = try await diarizer.diarizeOnDevice(request)
        #expect(result.clusters == fixtureResult.clusters)
    }

    @Test func test_mockSummarizer_defaultCannedResult_includesOneUngroundedClaim() async throws {
        let summarizer = MockSummarizer()
        let request = SummarizationRequest(
            meetingID: MeetingID(rawValue: UUID()),
            transcript: TranscriptWindow(meetingID: MeetingID(rawValue: UUID()), turns: []),
            template: SummaryTemplate(
                templateID: ShippedSummaryTemplate.standup.rawValue, templateVersion: "1", sections: [],
                sectionPromptFragments: [:], requiredLayers: [.flashRecap], requiredFields: [],
                toneDefault: .neutral, evidenceStrictness: .standard), layers: [.flashRecap], length: .brief,
            tone: .neutral, audience: .internalTeam, outputLanguages: [])

        let result = try await summarizer.summarizeOnDevice(request)
        let ungrounded = result.insights.filter { $0.evidence.isEmpty }
        #expect(ungrounded.count == 1)
        #expect(ungrounded[0].claimKind != .aiSuggests)
    }

    @Test func test_mockEmbedder_isDeterministicAcrossCalls() async throws {
        let embedder = MockEmbedder(dimensions: 4)
        let first = try await embedder.embedOnDevice(["hello world"])
        let second = try await embedder.embedOnDevice(["hello world"])
        #expect(first == second)
        #expect(first[0].vector.count == 4)
    }

    @Test func test_mockEmbedder_differentTextsProduceDifferentVectors() async throws {
        let embedder = MockEmbedder(dimensions: 4)
        let alphaVectors = try await embedder.embedOnDevice(["alpha"])
        let betaVectors = try await embedder.embedOnDevice(["beta"])
        #expect(alphaVectors != betaVectors)
    }

    @Test func test_mockRetriever_returnsFixtureChunks() async throws {
        let chunk = RetrievedChunk(meetingID: MeetingID(rawValue: UUID()), turnIDs: [], text: "hi", score: 1.0)
        let retriever = MockRetriever(fixtureChunks: [chunk])

        let result = try await retriever.retrieve(
            RetrievalQuery(text: "hi"), scope: .workspace(WorkspaceID(rawValue: UUID())))
        #expect(result == [chunk])
    }

    @Test func test_mockEntailmentChecker_defaultsToEntailed() async throws {
        let checker = MockEntailmentChecker()
        let claim = ClaimUnderTest(claimText: "x", spanText: "y", proposedKind: .said)

        let verdicts = try await checker.check([claim])
        guard case .entailed(let confidence) = verdicts.first else {
            Issue.record("expected .entailed by default")
            return
        }
        #expect(confidence == 1.0)
    }

    @Test func test_mockEntailmentChecker_returnsScriptedVerdicts() async throws {
        let checker = MockEntailmentChecker(scriptedVerdicts: [.contradicted(confidence: 0.9)])
        let claim = ClaimUnderTest(claimText: "x", spanText: "y", proposedKind: .said)

        let verdicts = try await checker.check([claim])
        #expect(verdicts == [.contradicted(confidence: 0.9)])
    }
}
