import Foundation
import NSPCore
import NSPPolicy

/// A request to transcribe already-closed, content-addressed segments
/// (docs/04 §2, verbatim). Audio never travels inline — `segments`
/// references it by `SegmentRef`, so a remote call's payload is exactly
/// what `NetworkGate` was asked to authorize, nothing more.
public struct TranscriptionRequest: Sendable {
    public let meetingID: MeetingID
    public let segments: [SegmentRef]
    public let expectedLanguages: [Locale.Language]
    public let glossary: [GlossaryEntry]
    /// Always `true` in production (docs/04 §2) — word timings are
    /// mandatory for tap-to-audio and evidence links.
    public let wantsWordTimings: Bool

    public init(
        meetingID: MeetingID, segments: [SegmentRef], expectedLanguages: [Locale.Language],
        glossary: [GlossaryEntry] = [], wantsWordTimings: Bool = true
    ) {
        self.meetingID = meetingID
        self.segments = segments
        self.expectedLanguages = expectedLanguages
        self.glossary = glossary
        self.wantsWordTimings = wantsWordTimings
    }
}

public struct TranscriptionResult: Sendable {
    public let turns: [TranscriptTurn]
    public let languageSpans: [LanguageSpan]
    public let meanConfidence: Double
    public let provenance: Provenance

    public init(
        turns: [TranscriptTurn], languageSpans: [LanguageSpan], meanConfidence: Double, provenance: Provenance
    ) {
        self.turns = turns
        self.languageSpans = languageSpans
        self.meanConfidence = meanConfidence
        self.provenance = provenance
    }
}

/// docs/04 §2, verbatim. Every method that can leave the device takes a
/// `ProcessingGrant` minted by `NSPPolicy` — there is no overload without
/// one (docs/01 §3). The on-device methods never leave, so they never need
/// one; `NetworkGate` re-validates a grant on every remote call regardless
/// of what the caller already believes about it.
public protocol TranscriberProtocol: Sendable {
    func transcribeOnDevice(_ request: TranscriptionRequest) async throws -> TranscriptionResult
    func transcribeRemote(_ request: TranscriptionRequest, grant: ProcessingGrant) async throws -> TranscriptionResult
    func streamOnDevice(_ request: StreamRequest) -> AsyncThrowingStream<PartialTranscript, Error>
    func streamRemote(_ request: StreamRequest, grant: ProcessingGrant) -> AsyncThrowingStream<PartialTranscript, Error>
    var capabilities: TranscriberCapabilities { get }
}
