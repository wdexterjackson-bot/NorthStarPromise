import Foundation

/// One of the user's existing calendar events, as much as a Scheduled
/// Recording import needs — never the full `EKEvent` (same "no EventKit
/// type leaks past this package" reasoning `CalendarInfo` already applies
/// to `EKCalendar`).
public struct CalendarEventInfo: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date

    public init(identifier: String, title: String, startDate: Date, endDate: Date) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }

    public var id: String { identifier }
}

/// Lists the user's existing calendar events, for Scheduled Recording's
/// "import from Calendar" path (docs/07 §2.1) — pick an event, its title/
/// start/end pre-fill the schedule. Kept as its own protocol/type rather
/// than folded into `CalendarEventWriter`: reading existing events needs
/// `EKEventStore.requestFullAccessToEvents()`, a materially broader grant
/// than the writer's `requestWriteOnlyAccessToEvents()`, and deserves its
/// own usage-description string and its own consent surface rather than
/// silently upgrading what the write-only grant implied. **Open risk**:
/// whether requesting full access interacts cleanly with an
/// already-granted write-only access, or double-prompts, needs a
/// Simulator/device spike — not verifiable by reading code (see
/// `EventKitCalendarEventReader`'s doc comment).
///
/// Protocol-injected so tests never touch real EventKit/Calendar data
/// (docs/11 §4).
public protocol CalendarEventReader: Sendable {
    func requestAccess() async -> CalendarAccessStatus
    /// Events starting within `window` — always a bounded near-future
    /// range, never an unbounded historical scan, matching docs/06's
    /// minimal-access ethos even under a full-access grant.
    func upcomingEvents(within window: DateInterval) async -> [CalendarEventInfo]
}
