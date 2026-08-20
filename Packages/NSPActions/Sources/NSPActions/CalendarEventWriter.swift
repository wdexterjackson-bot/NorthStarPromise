import Foundation

/// A calendar available as a write destination — deliberately not
/// `EKCalendar` itself, so nothing outside this package needs to import
/// EventKit (the same reasoning `CaptureBackend` in `NSPMedia` keeps
/// `AVAudioEngine` out of its callers' types).
public struct CalendarInfo: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let title: String

    public init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
    }

    public var id: String { identifier }
}

/// The exact payload a calendar-event write will create — what a
/// confirmation screen shows the user before `createEvent` is called
/// (Invariant I6: this is exactly the kind of write that must be
/// confirmed, not silent).
public struct CalendarEventDraft: Sendable, Hashable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarIdentifier: String

    public init(title: String, startDate: Date, endDate: Date, calendarIdentifier: String) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarIdentifier = calendarIdentifier
    }
}

public enum CalendarAccessStatus: Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
}

/// Typed, exhaustive error enum (docs/11 §2).
public enum CalendarWriterError: Error, Sendable, Hashable {
    case accessDenied
    case calendarNotFound
    case saveFailed(String)
}

/// Writes one event to a user-selected system calendar — "create a
/// calendar event for recordings" (docs/07 Settings § Calendar). This is
/// write-only by design: the app never reads the user's existing calendar
/// data, only ever creates new events the user has explicitly confirmed
/// (I6), matching `docs/06`'s minimal-access ethos. Protocol-injected so
/// tests never touch real EventKit/Calendar data (docs/11 §4).
public protocol CalendarEventWriter: Sendable {
    func requestAccess() async -> CalendarAccessStatus
    /// Calendars the user could plausibly write a new event into — never
    /// exposes existing events on any of them.
    func availableCalendars() async -> [CalendarInfo]
    /// Creates the event and returns its identifier, so a caller can keep
    /// a local reference (`Meeting.calendarEventID`) without re-deriving
    /// it. Caller must have already shown `draft` to the user for
    /// confirmation — this method itself does not gate on that.
    func createEvent(_ draft: CalendarEventDraft) async throws -> String
}
