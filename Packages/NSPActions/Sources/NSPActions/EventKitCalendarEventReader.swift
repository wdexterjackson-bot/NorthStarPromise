#if canImport(EventKit)
    import EventKit
    import Foundation

    /// The real `CalendarEventReader`, backed by `EKEventStore`. Same
    /// `#if canImport(EventKit)` gate as `EventKitCalendarEventWriter` (not
    /// available on watchOS, but this package still needs to compile there).
    ///
    /// Shares its `EKEventStore` with `EventKitCalendarEventWriter` rather
    /// than owning a second instance — `AppEnvironment` constructs one store
    /// and injects it into both, so the write-only and full-access grants
    /// aren't juggled by two independent `EKEventStore` lifecycles talking
    /// past each other. Whether requesting full access here, after
    /// write-only access may already have been granted to the shared store
    /// by the writer, behaves cleanly or double-prompts is **unverified** —
    /// flagged in `CalendarEventReader`'s doc comment as needing a real
    /// Simulator/device spike before the import UX ships, not something
    /// this implementation can assert its way past.
    public final class EventKitCalendarEventReader: CalendarEventReader, @unchecked Sendable {
        private let store: EKEventStore

        public init(store: EKEventStore) {
            self.store = store
        }

        public func requestAccess() async -> CalendarAccessStatus {
            do {
                let granted = try await store.requestFullAccessToEvents()
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        }

        public func upcomingEvents(within window: DateInterval) async -> [CalendarEventInfo] {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
            return store.events(matching: predicate)
                .map {
                    CalendarEventInfo(
                        identifier: $0.eventIdentifier, title: $0.title ?? "", startDate: $0.startDate,
                        endDate: $0.endDate)
                }
                .sorted { $0.startDate < $1.startDate }
        }
    }
#endif
