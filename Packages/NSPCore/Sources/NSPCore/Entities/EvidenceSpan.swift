/// Anchors one generated claim to the transcript and audio that support it
/// (Invariant I4, docs/02 §2 — verbatim schema). Must resolve to playable
/// audio and readable transcript, or be reported stale; stale evidence is
/// shown as such and never silently dropped.
public struct EvidenceSpan: Sendable, Hashable, Codable {
    public let meetingID: MeetingID
    public let turnIDs: [TranscriptTurnID]
    public let sampleRange: SampleRange
    /// Snapshot, so evidence survives a later transcript edit.
    public let quotedText: String
    /// Which revision produced `quotedText`.
    public let transcriptRevision: Int

    public init(
        meetingID: MeetingID,
        turnIDs: [TranscriptTurnID],
        sampleRange: SampleRange,
        quotedText: String,
        transcriptRevision: Int
    ) {
        self.meetingID = meetingID
        self.turnIDs = turnIDs
        self.sampleRange = sampleRange
        self.quotedText = quotedText
        self.transcriptRevision = transcriptRevision
    }
}
