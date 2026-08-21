import NSPCore
import NSPDesignSystem
import SwiftUI

/// Create — or edit — a Scheduled Recording (docs/07 §2.1): manual entry or
/// an imported calendar event, the mandatory notification's alert style,
/// and how far ahead of the start time it fires. `NavigationStack { Form {
/// ... } }` + toolbar cancellation/confirmation actions, following
/// `MeetingTitlePromptView.swift`'s exact shape.
struct ScheduleRecordingFormView: View {
    let environment: AppEnvironment
    /// `nil` creates a new schedule; non-nil edits this existing one in
    /// place (`Dashboard`/`Today`'s "Edit" action on an upcoming recording).
    var existingItem: ScheduledRecording?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var stop: Date
    @State private var alertStyle: ScheduledRecordingAlertStyle
    @State private var notifyLeadTime: TimeInterval
    @State private var calendarEventID: String?
    @State private var isShowingCalendarPicker = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var projects: [Project] = []
    @State private var selectedProjectID: ProjectID?
    @State private var newProjectName = ""

    /// None, 30s, 1m, 1m30, 2m, 2m30 (docs/07 §2.1: "None to 2 minutes and
    /// 30 seconds").
    private static let leadTimeOptions: [TimeInterval] = [0, 30, 60, 90, 120, 150]

    init(environment: AppEnvironment, existingItem: ScheduledRecording? = nil, onDone: @escaping () -> Void) {
        self.environment = environment
        self.existingItem = existingItem
        self.onDone = onDone
        _title = State(initialValue: existingItem?.title ?? "")
        _start = State(initialValue: existingItem?.scheduledStart ?? Date().addingTimeInterval(3600))
        _stop = State(initialValue: existingItem?.scheduledStop ?? Date().addingTimeInterval(3600 + 1800))
        _alertStyle = State(initialValue: existingItem?.alertStyle ?? .sound)
        _notifyLeadTime = State(initialValue: existingItem?.notifyLeadTime ?? 0)
        _calendarEventID = State(initialValue: existingItem?.calendarEventID)
        _selectedProjectID = State(initialValue: existingItem?.projectID)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stop > start
    }

    private static func leadTimeLabel(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "None" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return seconds == 0 ? "\(minutes) min" : "\(minutes)m \(seconds)s"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this recording") {
                    TextField("Title", text: $title)
                    Button("Import from Calendar") { isShowingCalendarPicker = true }
                }
                Section("When") {
                    DatePicker("Start", selection: $start)
                    DatePicker("Stop", selection: $stop)
                    if stop <= start {
                        Text("Stop time must be after the start time.")
                            .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                    }
                }
                Section("Project") {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("None").tag(ProjectID?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(ProjectID?.some(project.projectID))
                        }
                    }
                    HStack {
                        TextField("New project name", text: $newProjectName)
                        Button("Add") { Task { await addProject() } }
                            .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    Picker("Alert", selection: $alertStyle) {
                        Text("Sound").tag(ScheduledRecordingAlertStyle.sound)
                        Text("Vibrate").tag(ScheduledRecordingAlertStyle.vibrateOnly)
                        Text("Silent").tag(ScheduledRecordingAlertStyle.silent)
                    }
                    Picker("Reminder", selection: $notifyLeadTime) {
                        ForEach(Self.leadTimeOptions, id: \.self) { interval in
                            Text(Self.leadTimeLabel(interval)).tag(interval)
                        }
                    }
                } footer: {
                    Text(
                        "The reminder gives you Begin Recording Now, Cancel, or Begin at Start Time. Vibrate "
                            + "isn't guaranteed on every device/Focus setting.")
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle(existingItem == nil ? "Schedule a Recording" : "Edit Scheduled Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .sheet(isPresented: $isShowingCalendarPicker) {
                CalendarEventPickerView(environment: environment) { event in
                    title = event.title
                    start = event.startDate
                    stop = event.endDate
                    calendarEventID = event.identifier
                }
            }
            .task { await loadProjects() }
        }
    }

    private func loadProjects() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        projects = (try? await environment.projectRepository.fetchAll(workspaceID: workspaceID)) ?? []
    }

    private func addProject() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = environment.clock.now()
        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID, name: trimmed, createdAt: now,
            updatedAt: now)
        do {
            try await environment.projectRepository.insert(project, at: now)
            projects.append(project)
            selectedProjectID = project.projectID
            newProjectName = ""
        } catch {
            saveError = "\(error)"
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if var updated = existingItem {
                updated.title = trimmedTitle
                updated.scheduledStart = start
                updated.scheduledStop = stop
                updated.alertStyle = alertStyle
                updated.notifyLeadTime = notifyLeadTime
                updated.calendarEventID = calendarEventID
                updated.projectID = selectedProjectID
                try await environment.scheduledRecordingCoordinator.update(updated)
            } else {
                guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
                let now = environment.clock.now()
                let item = ScheduledRecording(
                    scheduledRecordingID: .generate(clock: environment.clock), workspaceID: workspaceID,
                    title: trimmedTitle, scheduledStart: start, scheduledStop: stop, alertStyle: alertStyle,
                    notifyLeadTime: notifyLeadTime, calendarEventID: calendarEventID, projectID: selectedProjectID,
                    createdAt: now, updatedAt: now)
                try await environment.scheduledRecordingCoordinator.create(item)
            }
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
