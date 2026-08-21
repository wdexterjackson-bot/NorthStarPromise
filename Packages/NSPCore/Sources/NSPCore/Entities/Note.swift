import Foundation

/// A standalone note — explicitly **not** a meeting, even when it carries
/// an attached recording ("a note with a recording that was created as a
/// note is still not a meeting"). No attendee/calendar metadata at all;
/// `originDeviceID`/`consentRecordID` stay `nil` until (if ever) the user
/// attaches a recording to it, at which point they're set exactly like a
/// `Meeting`'s are. Reuses `MeetingState` for the same reason `BrainDump`
/// does — the states in question describe capturing audio, not being a
/// meeting.
public struct Note: Sendable, Hashable, Codable, Identifiable {
    public let noteID: NoteID
    public var id: NoteID { noteID }
    public let workspaceID: WorkspaceID
    public var title: String

    /// `nil` until a recording is attached — a text/ink-only note never
    /// sets these.
    public var originDeviceID: DeviceID?
    public var consentRecordID: ConsentRecordID?

    public var startedAt: Date
    public var endedAt: Date?
    public var canonicalDuration: SampleDuration
    public var lifecycleState: MeetingState

    public let policyID: PolicyID
    public let processingMode: ProcessingMode

    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        noteID: NoteID,
        workspaceID: WorkspaceID,
        title: String,
        originDeviceID: DeviceID? = nil,
        consentRecordID: ConsentRecordID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        canonicalDuration: SampleDuration = .zero,
        lifecycleState: MeetingState,
        policyID: PolicyID,
        processingMode: ProcessingMode,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.noteID = noteID
        self.workspaceID = workspaceID
        self.title = title
        self.originDeviceID = originDeviceID
        self.consentRecordID = consentRecordID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.canonicalDuration = canonicalDuration
        self.lifecycleState = lifecycleState
        self.policyID = policyID
        self.processingMode = processingMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
