/// A scheduled recording's lifecycle (docs/07 §2.1). `missed` (nobody acted
/// before `scheduledStop` passed) and `cancelled` (the user deleted it
/// first) are kept distinct rather than collapsed into one "inactive" case
/// — same granularity `MeetingState`/`Availability` already use elsewhere —
/// since the Upcoming list shows different copy for each.
public enum ScheduledRecordingStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case pending
    case notified
    case started
    case completed
    case skipped
    case missed
    case cancelled
}

/// User-chosen per schedule at setup time, same mental model as the Clock
/// app's alarms — see `ScheduledRecordingNotificationScheduler`'s doc
/// comment for what each case actually does and doesn't guarantee on
/// today's platform.
public enum ScheduledRecordingAlertStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case sound
    case vibrateOnly
    case silent
}
