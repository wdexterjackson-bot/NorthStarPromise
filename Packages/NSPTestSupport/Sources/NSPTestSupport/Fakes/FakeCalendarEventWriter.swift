import Foundation
import NSPActions

/// In-memory `CalendarEventWriter` so tests never touch real EventKit/
/// Calendar data (docs/11 §4).
public actor FakeCalendarEventWriter: CalendarEventWriter {
    public private(set) var createdEvents: [CalendarEventDraft] = []
    public var accessStatus: CalendarAccessStatus
    public var calendars: [CalendarInfo]

    public init(accessStatus: CalendarAccessStatus = .authorized, calendars: [CalendarInfo] = []) {
        self.accessStatus = accessStatus
        self.calendars = calendars
    }

    public func requestAccess() async -> CalendarAccessStatus {
        accessStatus
    }

    public func availableCalendars() async -> [CalendarInfo] {
        calendars
    }

    public func createEvent(_ draft: CalendarEventDraft) async throws -> String {
        guard accessStatus == .authorized else { throw CalendarWriterError.accessDenied }
        guard calendars.contains(where: { $0.identifier == draft.calendarIdentifier }) else {
            throw CalendarWriterError.calendarNotFound
        }
        createdEvents.append(draft)
        return "fake-event-\(createdEvents.count)"
    }
}
