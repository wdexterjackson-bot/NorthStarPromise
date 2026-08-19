import Foundation
import NSPCore

/// A live-transcription request (docs/04 §2's `streamOnDevice`/
/// `streamRemote`) — the streaming counterpart to `TranscriptionRequest`,
/// for audio still arriving rather than closed segments.
public struct StreamRequest: Sendable {
    public let meetingID: MeetingID
    public let expectedLanguages: [Locale.Language]
    public let glossary: [GlossaryEntry]

    public init(meetingID: MeetingID, expectedLanguages: [Locale.Language], glossary: [GlossaryEntry] = []) {
        self.meetingID = meetingID
        self.expectedLanguages = expectedLanguages
        self.glossary = glossary
    }
}

/// One incremental caption emitted by `streamOnDevice`/`streamRemote`
/// (docs/04 §1.1's "provisional captions"). `isFinal` marks the point where
/// a provisional turn is superseded by a canonical one.
public struct PartialTranscript: Sendable {
    public let text: String
    public let isFinal: Bool
    public let sampleOffset: Int64

    public init(text: String, isFinal: Bool, sampleOffset: Int64) {
        self.text = text
        self.isFinal = isFinal
        self.sampleOffset = sampleOffset
    }
}

/// What one `TranscriberProtocol` implementation can do (docs/04 §2
/// `TranscriberProtocol.capabilities`).
public struct TranscriberCapabilities: Sendable, Hashable {
    public let supportedLanguages: [Locale.Language]
    public let supportsWordTimings: Bool
    public let supportsStreaming: Bool
    public let availability: ModelAvailability

    public init(
        supportedLanguages: [Locale.Language], supportsWordTimings: Bool, supportsStreaming: Bool,
        availability: ModelAvailability
    ) {
        self.supportedLanguages = supportedLanguages
        self.supportsWordTimings = supportsWordTimings
        self.supportsStreaming = supportsStreaming
        self.availability = availability
    }
}
