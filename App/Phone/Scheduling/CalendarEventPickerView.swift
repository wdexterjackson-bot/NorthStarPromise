import NSPActions
import NSPDesignSystem
import SwiftUI

/// Lists the user's existing calendar events in a bounded near-future
/// window so `ScheduleRecordingFormView` can import one — title/start/end
/// pre-fill the schedule. `List` style follows `LibraryView.swift`'s
/// existing idiom rather than inventing a new one.
struct CalendarEventPickerView: View {
    let environment: AppEnvironment
    let onSelect: (CalendarEventInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var events: [CalendarEventInfo] = []
    @State private var accessStatus: CalendarAccessStatus = .notDetermined
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if accessStatus != .authorized {
                    ContentUnavailableView(
                        "Calendar access needed", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Allow calendar access in Settings to import an event."))
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "No upcoming events", systemImage: "calendar",
                        description: Text("Events in the next two weeks will appear here."))
                } else {
                    List(events) { event in
                        Button {
                            onSelect(event)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                                Text(event.title.isEmpty ? "Untitled event" : event.title)
                                    .font(Typo.ui(14, .bold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text(event.startDate, style: .date) + Text(" · ") + Text(event.startDate, style: .time)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Import from Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        accessStatus = await environment.calendarEventReader.requestAccess()
        guard accessStatus == .authorized else {
            isLoading = false
            return
        }
        let now = environment.clock.now()
        let window = DateInterval(start: now, end: now.addingTimeInterval(14 * 24 * 3600))
        events = await environment.calendarEventReader.upcomingEvents(within: window)
        isLoading = false
    }
}
