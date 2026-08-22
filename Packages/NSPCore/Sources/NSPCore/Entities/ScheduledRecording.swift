import Foundation

/// A pre-scheduled recording (docs/07 §2.1): a name, a start time, and a
/// stop time, either typed in manually or imported from an existing
/// calendar event. `scheduledStart`/`scheduledStop` are display/scheduling
/// metadata — the same category `Meeting.startedAt`/`endedAt` already are,
/// never timeline math (`docs/11` §4, "No Date() in domain logic"; see
/// `ScheduledRecordingScheduling` for the one place wall-clock arithmetic
/// over these fields is allowed to happen).
///
/// No throwing init: `scheduledStop > scheduledStart` and "both in the
/// future" are validated in the create form, matching
/// `MeetingTitlePromptView.save()`'s existing trim-and-guard style rather
/// than a new validation convention at the domain-type layer.
public struct ScheduledRecording: Sendable, Hashable, Codable, Identifiable {
    public let scheduledRecordingID: ScheduledRecordingID
    public var id: ScheduledRecordingID { scheduledRecordingID }
    public let workspaceID: WorkspaceID

    public var title: String
    public var scheduledStart: Date
    public var scheduledStop: Date
    public var status: ScheduledRecordingStatus
    public var alertStyle: ScheduledRecordingAlertStyle
    /// Seconds before `scheduledStart` the reminder notification fires —
    /// `0` ("None") means it fires exactly at the start time. Ranges
    /// 0...150 (docs/07 §2.1: "None to 2 minutes and 30 seconds").
    public var notifyLeadTime: TimeInterval

    /// Set only when created via calendar import — an external `EKEvent`
    /// identifier, same "plain nullable text, no FK" precedent as
    /// `Meeting.calendarEventID`.
    public var calendarEventID: String?

    /// Set once Start is tapped and `RecordingSession.start()` has created
    /// or promoted the real `Meeting` row, so the Upcoming list (and a
    /// future "view the recording" link) can resolve schedule → meeting.
    public var meetingID: MeetingID?
    /// Chosen at scheduling time — applied to the resulting `Meeting` the
    /// moment it's created (`ScheduledRecordingCoordinator.handleStartAction`),
    /// same project-linking mechanism `MeetingTitlePromptView`'s and
    /// `OverviewTab`'s project pickers use.
    public var projectID: ProjectID?

    /// Which agenda-row rail color this item displays (`Palette
    /// .threadSlots`, indices 0...5) — chosen at creation via
    /// `AddAgendaItemFormView`'s color picker.
    public var colorSlot: Int

    /// Set when this scheduled item is one occurrence of a recurring
    /// series (NSP-157). `nil` for an ordinary, non-recurring item.
    public var recurrenceRuleID: RecurrenceRuleID?

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        scheduledRecordingID: ScheduledRecordingID,
        workspaceID: WorkspaceID,
        title: String,
        scheduledStart: Date,
        scheduledStop: Date,
        status: ScheduledRecordingStatus = .pending,
        alertStyle: ScheduledRecordingAlertStyle = .sound,
        notifyLeadTime: TimeInterval = 0,
        calendarEventID: String? = nil,
        meetingID: MeetingID? = nil,
        projectID: ProjectID? = nil,
        colorSlot: Int = 0,
        recurrenceRuleID: RecurrenceRuleID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.scheduledRecordingID = scheduledRecordingID
        self.workspaceID = workspaceID
        self.title = title
        self.scheduledStart = scheduledStart
        self.scheduledStop = scheduledStop
        self.status = status
        self.alertStyle = alertStyle
        self.notifyLeadTime = notifyLeadTime
        self.calendarEventID = calendarEventID
        self.meetingID = meetingID
        self.projectID = projectID
        self.colorSlot = colorSlot
        self.recurrenceRuleID = recurrenceRuleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
