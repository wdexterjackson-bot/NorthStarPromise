import NSPCore
import NSPPolicy

/// A speaker-diarization request over already-closed segments.
public struct DiarizationRequest: Sendable {
    public let meetingID: MeetingID
    public let segments: [SegmentRef]
    public let expectedSpeakerCount: Int?

    public init(meetingID: MeetingID, segments: [SegmentRef], expectedSpeakerCount: Int? = nil) {
        self.meetingID = meetingID
        self.segments = segments
        self.expectedSpeakerCount = expectedSpeakerCount
    }
}

/// One turn's cluster assignment (docs/04 §2's `DiarizationResult.assignments`
/// tuple, reified as a named type — SwiftLint's `large_tuple` rule caps
/// tuples at 2 members; this carries the identical 3 fields).
public struct SpeakerAssignment: Sendable, Hashable {
    public let turnID: TranscriptTurnID
    public let clusterID: String
    public let confidence: Double

    public init(turnID: TranscriptTurnID, clusterID: String, confidence: Double) {
        self.turnID = turnID
        self.clusterID = clusterID
        self.confidence = confidence
    }
}

public struct DiarizationResult: Sendable {
    public let clusters: [SpeakerCluster]
    public let assignments: [SpeakerAssignment]

    public init(clusters: [SpeakerCluster], assignments: [SpeakerAssignment]) {
        self.clusters = clusters
        self.assignments = assignments
    }
}

/// docs/04 §2, verbatim.
public protocol DiarizerProtocol: Sendable {
    func diarizeOnDevice(_ request: DiarizationRequest) async throws -> DiarizationResult
    func diarizeRemote(_ request: DiarizationRequest, grant: ProcessingGrant) async throws -> DiarizationResult
}
