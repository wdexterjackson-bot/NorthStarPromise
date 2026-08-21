import Foundation

/// What to run after a recording stops — chosen by the user in
/// `MeetingTitlePromptView`, defaulted to everything on. `generateTranscript`
/// gates the other two: transcription is a hard prerequisite for both
/// minutes and action items in `IntelligenceCoordinator.processMeeting`, so
/// turning it off is what actually skips the whole pipeline, not a
/// per-artifact opt-out on its own.
public struct PostRecordingProcessingOptions: Sendable, Equatable {
    public var generateTranscript: Bool
    public var generateMinutes: Bool
    public var generateActionItems: Bool

    public init(generateTranscript: Bool = true, generateMinutes: Bool = true, generateActionItems: Bool = true) {
        self.generateTranscript = generateTranscript
        self.generateMinutes = generateMinutes
        self.generateActionItems = generateActionItems
    }
}
