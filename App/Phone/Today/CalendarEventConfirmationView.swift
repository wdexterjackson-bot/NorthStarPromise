import NSPActions
import NSPCore
import NSPDesignSystem
import SwiftUI

/// The I6 gate for "create a calendar event for this recording" (Settings
/// § Calendar): shows the exact payload — title, calendar, start, end —
/// and requires an explicit tap before anything is written. Per the
/// product spec, only the start time is user-adjustable, defaulting to
/// the 15-minute increment before the recording actually started (a 2:11pm
/// start defaults to 2:00pm) — people's meetings usually start a few
/// minutes before anyone hits record.
struct CalendarEventConfirmationView: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let onDone: () -> Void

    @State private var startDate: Date
    @State private var isSaving = false
    @State private var saveError: String?

    init(meeting: Meeting, environment: AppEnvironment, onDone: @escaping () -> Void) {
        self.meeting = meeting
        self.environment = environment
        self.onDone = onDone
        _startDate = State(initialValue: Self.defaultStart(for: meeting.startedAt))
    }

    private var titleText: String {
        meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title
    }

    private var endDate: Date {
        max(meeting.endedAt ?? startDate, startDate.addingTimeInterval(60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add to Calendar") {
                    LabeledContent("Title", value: titleText)
                    DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    LabeledContent("Ends", value: endDate.formatted(date: .omitted, time: .shortened))
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let calendarIdentifier = environment.selectedCalendarIdentifier else {
            onDone()
            return
        }
        isSaving = true
        defer { isSaving = false }

        let draft = CalendarEventDraft(
            title: titleText, startDate: startDate, endDate: endDate, calendarIdentifier: calendarIdentifier)
        do {
            let eventIdentifier = try await environment.calendarEventWriter.createEvent(draft)
            var updated = meeting
            updated.calendarEventID = eventIdentifier
            try await environment.meetingRepository.update(updated, at: environment.clock.now())
            onDone()
        } catch {
            saveError = "\(error)"
        }
    }

    /// Rounds down to the nearest 15-minute mark — 2:11pm → 2:00pm.
    private static func defaultStart(for recordingStart: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: recordingStart)
        let roundedMinute = (minute / 15) * 15
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: recordingStart), minute: roundedMinute, second: 0,
            of: recordingStart) ?? recordingStart
    }
}
