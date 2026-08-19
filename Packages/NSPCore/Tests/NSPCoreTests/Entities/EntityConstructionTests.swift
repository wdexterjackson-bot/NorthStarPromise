import Foundation
import Testing

@testable import NSPCore

@Suite("Entity construction and Codable round-trip")
struct EntityConstructionTests {
    static let clock = SystemClock()

    @Test func test_meeting_codable_roundTrips() throws {
        let meeting = Meeting(
            meetingID: .generate(clock: Self.clock),
            workspaceID: .generate(clock: Self.clock),
            title: "Weekly sync",
            captureMode: .watch,
            originDeviceID: .generate(clock: Self.clock),
            startedAt: Date(),
            lifecycleState: .recording,
            policyID: .generate(clock: Self.clock),
            processingMode: .localOnly,
            availability: .complete,
            createdAt: Date(),
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(meeting)
        let decoded = try JSONDecoder().decode(Meeting.self, from: data)

        #expect(decoded == meeting)
    }

    @Test func test_segment_codable_roundTrips() throws {
        let segment = Segment(
            segmentID: .generate(clock: Self.clock),
            meetingID: .generate(clock: Self.clock),
            deviceID: .generate(clock: Self.clock),
            sequence: 0,
            codec: .aacLC,
            sampleRate: 16000,
            channels: 1,
            bitRate: 32000,
            startSample: 0,
            sampleCount: 960_000
        )

        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(Segment.self, from: data)

        #expect(decoded == segment)
    }

    @Test func test_evidenceSpan_codable_roundTrips() throws {
        let span = EvidenceSpan(
            meetingID: .generate(clock: Self.clock),
            turnIDs: [.generate(clock: Self.clock)],
            sampleRange: SampleRange(startSample: 0, endSample: 16000),
            quotedText: "we agreed to ship Friday",
            transcriptRevision: 1
        )

        let data = try JSONEncoder().encode(span)
        let decoded = try JSONDecoder().decode(EvidenceSpan.self, from: data)

        #expect(decoded == span)
    }

    @Test func test_action_withoutEvidence_isRepresentable_asAISuggestsOnly() {
        // The type does not forbid empty evidence — NSPIntelligence is
        // responsible for never emitting `.said`/`.agreed` without it
        // (Invariant I4). This test documents that boundary.
        let action = Action(
            actionID: .generate(clock: Self.clock),
            meetingID: .generate(clock: Self.clock),
            text: "Follow up with legal",
            evidence: [],
            createdBy: .generate(clock: Self.clock)
        )

        #expect(action.evidence.isEmpty)
        #expect(action.status == .proposed)
    }

    @Test func test_insight_emptyEvidence_mustBeAISuggests_byConvention() {
        let insight = Insight(
            insightID: .generate(clock: Self.clock),
            meetingID: .generate(clock: Self.clock),
            layer: .flashRecap,
            text: "The team may consider revisiting the timeline",
            claimKind: .aiSuggests,
            evidence: [],
            confidence: 0.4,
            provenance: Provenance(
                modelID: "on-device-summarizer",
                modelVersion: "1",
                promptVersion: "1",
                generatedAt: Date(),
                processingPlane: .onDevice)
        )

        #expect(insight.evidence.isEmpty)
        #expect(insight.claimKind == .aiSuggests)
    }
}
