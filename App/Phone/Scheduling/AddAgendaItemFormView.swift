import NSPCore
import NSPDesignSystem
import SwiftUI

/// The Today's Agenda "+" flow (`PadDashboardSidebar.agendaSection`):
/// name/time/project fields identical to `ScheduleRecordingFormView`, plus
/// one choice that view doesn't have — whether this item should record
/// itself automatically at its start time, or exist as a placeholder the
/// user fills in later (walk into the room, import the recording
/// afterward). The two answers route to genuinely different persistence:
///
/// - **Record automatically**: exactly `ScheduleRecordingFormView`'s
///   existing path — a `ScheduledRecording` + its notification, unchanged.
/// - **Not now**: a bare `Meeting` row, `lifecycleState: .ready` (the same
///   state `RecordingSession.prepareDraft()` uses for "exists, nothing
///   captured yet"), so it appears on Today's Agenda immediately rather
///   than waiting for a notification to fire — `DashboardComposer` reads
///   real `Meeting` rows only, never pending schedules. Its Audio tab stays
///   empty until an import happens (`AudioTab`'s "Import Recording"
///   affordance), at which point `IntelligenceCoordinator.processMeeting`
///   runs automatically, same as any other recording finishing.
struct AddAgendaItemFormView: View {
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date().addingTimeInterval(3600)
    @State private var stop = Date().addingTimeInterval(3600 + 1800)
    @State private var recordAutomatically = true
    @State private var alertStyle: ScheduledRecordingAlertStyle = .sound
    @State private var notifyLeadTime: TimeInterval = 0
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var projects: [Project] = []
    @State private var selectedProjectID: ProjectID?
    @State private var newProjectName = ""

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stop > start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this meeting") {
                    TextField("Title", text: $title)
                }
                Section("When") {
                    DatePicker("Start", selection: $start)
                    DatePicker("Stop", selection: $stop)
                    if stop <= start {
                        Text("Stop time must be after the start time.")
                            .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                    }
                }
                Section {
                    Toggle("Record automatically at the start time", isOn: $recordAutomatically)
                } footer: {
                    Text(
                        recordAutomatically
                            ? "A reminder fires at the start time with Begin Recording Now, Cancel, or Begin at "
                                + "Start Time."
                            : "This meeting appears on today's agenda now with no audio yet. Import a recording "
                                + "for it any time from its Audio tab — notes, transcript, and action items are "
                                + "generated automatically once you do.")
                }
                if recordAutomatically {
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
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Add to Today's Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .task { await loadProjects() }
        }
    }

    /// None, 30s, 1m, 1m30, 2m, 2m30 — same set `ScheduleRecordingFormView` offers.
    private static let leadTimeOptions: [TimeInterval] = [0, 30, 60, 90, 120, 150]

    private static func leadTimeLabel(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "None" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return seconds == 0 ? "\(minutes) min" : "\(minutes)m \(seconds)s"
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
        do {
            if recordAutomatically {
                try await saveScheduledRecording()
            } else {
                try await saveBareMeeting()
            }
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }

    private func saveScheduledRecording() async throws {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.clock.now()
        let item = ScheduledRecording(
            scheduledRecordingID: .generate(clock: environment.clock), workspaceID: workspaceID, title: trimmedTitle,
            scheduledStart: start, scheduledStop: stop, alertStyle: alertStyle, notifyLeadTime: notifyLeadTime,
            projectID: selectedProjectID, createdAt: now, updatedAt: now)
        try await environment.scheduledRecordingCoordinator.create(item)
    }

    /// A `Meeting` row with no segments yet — `.ready`, the same lifecycle
    /// state `RecordingSession.prepareDraft()` leaves a pre-recording draft
    /// in, so this shell is later importable (`AudioTab`) exactly like one.
    private func saveBareMeeting() async throws {
        guard let policy = environment.defaultPolicy else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.clock.now()
        // `endedAt` stays nil — nothing has actually ended yet. Once `start`
        // passes with no recording, the agenda row's own state derivation
        // (`DashboardComposer.rowState`, `end = endedAt ?? startedAt`) reads
        // this as `.past` rather than fabricating a "live" window nothing
        // backs.
        let meeting = Meeting(
            meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID, title: trimmedTitle,
            captureMode: .import, originDeviceID: environment.deviceID, startedAt: start, lifecycleState: .ready,
            policyID: policy.policyID, processingMode: policy.defaultProcessingMode, availability: .complete,
            createdAt: now, updatedAt: now)
        try await environment.meetingRepository.insert(meeting, at: now)
        if let selectedProjectID {
            try? await environment.projectRepository.setProjects(
                for: meeting.meetingID, projectIDs: [selectedProjectID])
        }
    }
}
