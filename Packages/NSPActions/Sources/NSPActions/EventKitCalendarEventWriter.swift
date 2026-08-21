#if canImport(EventKit)
    import EventKit
    import Foundation

    /// The real `CalendarEventWriter`, backed by `EKEventStore`. EventKit
    /// isn't available on watchOS (this package still needs to compile
    /// there, since `NSPActions` is a supported-platform target) — gated
    /// with `#if canImport(EventKit)` rather than `#if os(iOS)` since the
    /// same code also works on macOS for `swift test`.
    public final class EventKitCalendarEventWriter: CalendarEventWriter, @unchecked Sendable {
        private let store: EKEventStore

        /// Defaults to a fresh store so every existing call site
        /// (`EventKitCalendarEventWriter()`) keeps compiling unchanged.
        /// `AppEnvironment` passes a store shared with
        /// `EventKitCalendarEventReader` instead — see that type's doc
        /// comment for why sharing one store matters here.
        public init(store: EKEventStore = EKEventStore()) {
            self.store = store
        }

        public func requestAccess() async -> CalendarAccessStatus {
            do {
                let granted = try await store.requestWriteOnlyAccessToEvents()
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        }

        public func availableCalendars() async -> [CalendarInfo] {
            store.calendars(for: .event)
                .filter(\.allowsContentModifications)
                .map { CalendarInfo(identifier: $0.calendarIdentifier, title: $0.title) }
        }

        public func createEvent(_ draft: CalendarEventDraft) async throws -> String {
            guard let calendar = store.calendar(withIdentifier: draft.calendarIdentifier) else {
                throw CalendarWriterError.calendarNotFound
            }
            let event = EKEvent(eventStore: store)
            event.title = draft.title
            event.startDate = draft.startDate
            event.endDate = draft.endDate
            event.calendar = calendar
            do {
                try store.save(event, span: .thisEvent)
            } catch {
                throw CalendarWriterError.saveFailed("\(error)")
            }
            guard let identifier = event.eventIdentifier else {
                throw CalendarWriterError.saveFailed("EventKit returned no event identifier after save")
            }
            return identifier
        }
    }
#endif
