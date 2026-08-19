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
    public var calendarEventID: String?

    public let captureMode: CaptureMode
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

    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        meetingID: MeetingID,
        workspaceID: WorkspaceID,
        title: String,
        isTitleSensitive: Bool = false,
        calendarEventID: String? = nil,
        captureMode: CaptureMode,
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
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.meetingID = meetingID
        self.workspaceID = workspaceID
        self.title = title
        self.isTitleSensitive = isTitleSensitive
        self.calendarEventID = calendarEventID
        self.captureMode = captureMode
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
