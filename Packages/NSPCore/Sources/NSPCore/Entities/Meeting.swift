import Foundation

/// The root aggregate: one recorded meeting and its lifecycle (docs/02 §2).
public struct Meeting: Sendable, Hashable, Codable, Identifiable {
    public let meetingID: MeetingID
    public var id: MeetingID { meetingID }
    public let workspaceID: WorkspaceID

    /// May originate from a calendar event. Treat as sensitive when
    /// `isTitleSensitive` is set — never log it (docs/11 §9).
    public var title: String
    public var isTitleSensitive: Bool
    /// A second, smaller title-band line — iPad's ruled-paper canvas
    /// (docs/07 §5's mockup: "Concentrix" / "Onsite Visit and QBR"). Free
    /// text the user edits directly on the page; no other screen shows it
    /// yet.
    public var subtitle: String?
    public var calendarEventID: String?

    public let captureMode: CaptureMode
    /// What this recording is *for* (docs/07's dual Dashboard start
    /// actions: "Start Recording a Meeting" vs. "Record a Mental Note") —
    /// orthogonal to `captureMode`, which is about the capturing device,
    /// not the user's intent.
    public var recordingIntent: RecordingIntent
    public let originDeviceID: DeviceID

    /// Display and cross-device anchoring only — never timeline math.
    public var startedAt: Date
    public var endedAt: Date?

    public var canonicalDuration: SampleDuration
    public var lifecycleState: MeetingState

    public let policyID: PolicyID
    /// Frozen at Arming; no API path may mutate this after (Invariant I5).
    public let processingMode: ProcessingMode
    public var consentRecordID: ConsentRecordID?

    public var availability: Availability
    public var excludedFromMemory: Bool

    /// Which agenda-row rail color this meeting displays (`Palette
    /// .threadSlots`, indices 0...5) — chosen at creation via
    /// `AddAgendaItemFormView`'s color picker, independent of any Thread
    /// membership. A meeting with a Thread still shows that Thread's color
    /// instead (`PadAgendaRow.railColor`); this only matters for meetings
    /// with no Thread.
    public var colorSlot: Int
    /// `.recorded` for every ordinarily-captured meeting; `.notesOnly`/
    /// `.reminder` for the two no-audio-expected shells the "Add to Today's
    /// Agenda" flow can create directly instead of a `ScheduledRecording`.
    public var kind: MeetingKind

    /// Set when this meeting is one occurrence of a recurring series
    /// (NSP-157) — either the still-virtual series' first real promotion,
    /// or a `RecurrenceException.modified` override for one later date.
    /// `nil` for an ordinary, non-recurring meeting.
    public var recurrenceRuleID: RecurrenceRuleID?

    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        meetingID: MeetingID,
        workspaceID: WorkspaceID,
        title: String,
        isTitleSensitive: Bool = false,
        subtitle: String? = nil,
        calendarEventID: String? = nil,
        captureMode: CaptureMode,
        recordingIntent: RecordingIntent = .meeting,
        originDeviceID: DeviceID,
        startedAt: Date,
        endedAt: Date? = nil,
        canonicalDuration: SampleDuration = .zero,
        lifecycleState: MeetingState,
        policyID: PolicyID,
        processingMode: ProcessingMode,
        consentRecordID: ConsentRecordID? = nil,
        availability: Availability,
        excludedFromMemory: Bool = false,
        colorSlot: Int = 0,
        kind: MeetingKind = .recorded,
        recurrenceRuleID: RecurrenceRuleID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.meetingID = meetingID
        self.workspaceID = workspaceID
        self.title = title
        self.isTitleSensitive = isTitleSensitive
        self.subtitle = subtitle
        self.calendarEventID = calendarEventID
        self.captureMode = captureMode
        self.recordingIntent = recordingIntent
        self.originDeviceID = originDeviceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.canonicalDuration = canonicalDuration
        self.lifecycleState = lifecycleState
        self.policyID = policyID
        self.processingMode = processingMode
        self.consentRecordID = consentRecordID
        self.availability = availability
        self.excludedFromMemory = excludedFromMemory
        self.colorSlot = colorSlot
        self.kind = kind
        self.recurrenceRuleID = recurrenceRuleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
