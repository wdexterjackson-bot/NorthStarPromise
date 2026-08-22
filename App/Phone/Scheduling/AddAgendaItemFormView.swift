import NSPCore
import NSPDesignSystem
import SwiftUI

/// The Today's Agenda "+" flow (`PadDashboardSidebar.agendaSection`), and
/// also the "Modify Event" destination for a bare-`Meeting`/
/// `ScheduledRecording`/reminder-`Action` agenda row (`PadAgendaRow`'s "…"
/// menu) — passing `existingMeeting`/`existingScheduledRecording`/
/// `existingReminderAction` switches every save into an update of that row
/// instead of a fresh insert. Three Meeting Types, each routing to
/// genuinely different persistence:
///
/// - **Recorded Meeting**: a `ScheduledRecording` + its mandatory Start/Skip
///   notification (`ScheduledRecordingCoordinator`).
/// - **Meeting with Notes**: a bare `Meeting` row, `.notesOnly` kind,
///   `lifecycleState: .ready` (the same state `RecordingSession
///   .prepareDraft()` uses for "exists, nothing captured yet"), so it
///   appears on Today's Agenda immediately rather than waiting for a
///   notification to fire — `DashboardComposer` reads real `Meeting` rows
///   only, never pending schedules. Its Audio tab stays empty until an
///   import happens (`AudioTab`'s "Import Recording" affordance), at which
///   point `IntelligenceCoordinator.processMeeting` runs automatically, same
///   as any other recording finishing.
/// - **Action Reminder**: a plain, due-dated, no-meeting `Action` — never a
///   phantom `Meeting` row ("The Spine" recommendation, 2026-08-22,
///   `Migration022CollapseActionReminders`), so it shows up on a Person's
///   page, counts in Needs You, and participates in every relationship
///   query like any other commitment. Color and recurrence don't apply to
///   a plain `Action`, so those controls hide for this type.
enum AddAgendaItemError: LocalizedError {
    case noWorkspace

    var errorDescription: String? {
        "No workspace is set up yet — restart the app and try again."
    }
}

private enum AgendaMeetingType: String, CaseIterable, Identifiable {
    case recordedMeeting
    case meetingWithNotes
    case actionReminder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recordedMeeting: return "Recorded Meeting"
        case .meetingWithNotes: return "Meeting with Notes"
        case .actionReminder: return "Action Reminder"
        }
    }
}

struct AddAgendaItemFormView: View {
    let environment: AppEnvironment
    let onDone: () -> Void
    var existingMeeting: Meeting?
    var existingScheduledRecording: ScheduledRecording?
    var existingReminderAction: Action?
    /// Seeds Start/Stop's *date* (keeping the usual "an hour from now" time
    /// of day) when creating fresh — `CalendarView`'s "+" passes the day
    /// currently selected in the grid, so a new item lands on the day the
    /// user was actually looking at rather than always today.
    var initialDate: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date().addingTimeInterval(3600)
    @State private var stop = Date().addingTimeInterval(3600 + 1800)
    @State private var meetingType: AgendaMeetingType = .recordedMeeting
    @State private var colorSlot = 0
    @State private var alertStyle: ScheduledRecordingAlertStyle = .sound
    @State private var notifyLeadTime: TimeInterval = 0
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var projects: [Project] = []
    @State private var selectedProjectID: ProjectID?
    @State private var newProjectName = ""
    @State private var hasLoadedExisting = false
    @State private var recurrenceFrequency: RecurrenceFrequency?
    @State private var recurrenceEnd: RecurrenceEnd = .never
    @State private var existingRecurrenceRuleID: RecurrenceRuleID?
    @State private var isConfiguringRecurrence = false

    private var isEditing: Bool {
        existingMeeting != nil || existingScheduledRecording != nil || existingReminderAction != nil
    }

    private var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return meetingType == .actionReminder ? hasTitle : hasTitle && stop > start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this meeting") {
                    TextField("Title", text: $title)
                }
                Section("When") {
                    DatePicker("Start", selection: $start)
                    if meetingType != .actionReminder {
                        DatePicker("Stop", selection: $stop)
                        if stop <= start {
                            Text("Stop time must be after the start time.")
                                .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                        }
                    }
                }
                if meetingType != .actionReminder {
                    Section {
                        Button {
                            isConfiguringRecurrence = true
                        } label: {
                            if let recurrenceFrequency {
                                Text(RecurrenceSummary.text(for: recurrenceFrequency))
                            } else {
                                Text("Make Event Recurring")
                            }
                        }
                    }
                }
                Section {
                    Picker("Meeting Type", selection: $meetingType) {
                        ForEach(AgendaMeetingType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                } footer: {
                    Text(footerText)
                }
                if meetingType != .actionReminder {
                    Section("Color") {
                        colorSwatches
                    }
                }
                if meetingType == .recordedMeeting {
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
                if meetingType != .actionReminder {
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
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle(isEditing ? "Edit Agenda Item" : "Add to Today's Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .task {
                await loadProjects()
                loadExistingIfNeeded()
                await loadExistingRecurrenceRuleIfNeeded()
            }
            .sheet(isPresented: $isConfiguringRecurrence) {
                RecurrenceConfigurationView(
                    seriesStart: start, initialFrequency: recurrenceFrequency, initialEnd: recurrenceEnd,
                    onDone: { frequency, end in
                        recurrenceFrequency = frequency
                        recurrenceEnd = end
                    },
                    onRemove: recurrenceFrequency == nil ? nil : { recurrenceFrequency = nil })
            }
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: 14) {
            ForEach(Palette.threadSlots.indices, id: \.self) { slot in
                Button {
                    colorSlot = slot
                } label: {
                    Circle()
                        .fill(Palette.threadSlots[slot])
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().strokeBorder(Palette.textPrimary, lineWidth: colorSlot == slot ? 2 : 0)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(colorSlot == slot ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(slot + 1)")
                .accessibilityAddTraits(colorSlot == slot ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var footerText: String {
        switch meetingType {
        case .recordedMeeting:
            return "A reminder fires at the start time with Begin Recording Now, Cancel, or Begin at Start Time."
        case .meetingWithNotes:
            return "This meeting appears on today's agenda now with no audio yet. Import a recording for it any "
                + "time from its Audio tab — notes, transcript, and action items are generated automatically once "
                + "you do."
        case .actionReminder:
            return "A placeholder reminder on today's agenda — no recording is ever expected for it."
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

    private func loadExistingIfNeeded() {
        guard !hasLoadedExisting else { return }
        hasLoadedExisting = true
        if let item = existingScheduledRecording {
            title = item.title
            start = item.scheduledStart
            stop = item.scheduledStop
            meetingType = .recordedMeeting
            alertStyle = item.alertStyle
            notifyLeadTime = item.notifyLeadTime
            selectedProjectID = item.projectID
            colorSlot = item.colorSlot
        } else if let meeting = existingMeeting {
            title = meeting.isTitleSensitive ? "" : meeting.title
            start = meeting.startedAt
            stop = meeting.endedAt ?? meeting.startedAt.addingTimeInterval(1800)
            meetingType = .meetingWithNotes
            colorSlot = meeting.colorSlot
        } else if let action = existingReminderAction {
            title = action.text
            meetingType = .actionReminder
            switch action.date {
            case .explicit(let date), .inferred(let date): start = date
            case .unresolved: break
            }
        } else if let initialDate {
            let calendar = Calendar.current
            let seededStart =
                calendar.date(
                    bySettingHour: calendar.component(.hour, from: start),
                    minute: calendar.component(.minute, from: start), second: 0, of: initialDate) ?? initialDate
            start = seededStart
            stop = seededStart.addingTimeInterval(1800)
        }
    }

    /// Loads the existing series' configuration into the in-memory
    /// `recurrenceFrequency`/`recurrenceEnd` state so an edit shows what's
    /// already there — the actual scope of *what* an edit here rewrites
    /// (this occurrence vs. the whole series) is `NSP-159`'s concern, at
    /// the agenda row's "…" menu, not this form.
    private func loadExistingRecurrenceRuleIfNeeded() async {
        let ruleID = existingScheduledRecording?.recurrenceRuleID ?? existingMeeting?.recurrenceRuleID
        guard let ruleID else { return }
        guard let rule = try? await environment.recurrenceRuleRepository.find(ruleID) else { return }
        existingRecurrenceRuleID = ruleID
        recurrenceFrequency = rule.frequency
        recurrenceEnd = rule.end
    }

    /// Creates, updates, or deletes the `RecurrenceRule` row to match the
    /// in-memory `recurrenceFrequency` state, returning the ID to stamp
    /// onto the `Meeting`/`ScheduledRecording` being saved (`nil` if this
    /// event isn't recurring).
    private func resolveRecurrenceRuleID(workspaceID: WorkspaceID, now: Date) async throws -> RecurrenceRuleID? {
        guard let recurrenceFrequency else {
            if let existingRecurrenceRuleID {
                try? await environment.recurrenceRuleRepository.delete(existingRecurrenceRuleID)
            }
            return nil
        }
        if let existingRecurrenceRuleID {
            let rule = RecurrenceRule(
                recurrenceRuleID: existingRecurrenceRuleID, workspaceID: workspaceID, frequency: recurrenceFrequency,
                end: recurrenceEnd, createdAt: now, updatedAt: now)
            try await environment.recurrenceRuleRepository.update(rule, at: now)
            return existingRecurrenceRuleID
        }
        let rule = RecurrenceRule(
            recurrenceRuleID: .generate(clock: environment.clock), workspaceID: workspaceID,
            frequency: recurrenceFrequency, end: recurrenceEnd, createdAt: now, updatedAt: now)
        try await environment.recurrenceRuleRepository.insert(rule, at: now)
        return rule.recurrenceRuleID
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
            switch meetingType {
            case .recordedMeeting: try await saveScheduledRecording()
            case .meetingWithNotes: try await saveBareMeeting(kind: .notesOnly)
            case .actionReminder: try await saveReminderAction()
            }
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }

    private func saveScheduledRecording() async throws {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else {
            throw AddAgendaItemError.noWorkspace
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.clock.now()
        let recurrenceRuleID = try await resolveRecurrenceRuleID(workspaceID: workspaceID, now: now)
        if let existing = existingScheduledRecording {
            var updated = existing
            updated.title = trimmedTitle
            updated.scheduledStart = start
            updated.scheduledStop = stop
            updated.alertStyle = alertStyle
            updated.notifyLeadTime = notifyLeadTime
            updated.projectID = selectedProjectID
            updated.colorSlot = colorSlot
            updated.recurrenceRuleID = recurrenceRuleID
            try await environment.scheduledRecordingCoordinator.update(updated)
        } else {
            let item = ScheduledRecording(
                scheduledRecordingID: .generate(clock: environment.clock), workspaceID: workspaceID,
                title: trimmedTitle, scheduledStart: start, scheduledStop: stop, alertStyle: alertStyle,
                notifyLeadTime: notifyLeadTime, projectID: selectedProjectID, colorSlot: colorSlot,
                recurrenceRuleID: recurrenceRuleID, createdAt: now, updatedAt: now)
            try await environment.scheduledRecordingCoordinator.create(item)
        }
    }

    /// A `Meeting` row with no segments yet — `.ready`, the same lifecycle
    /// state `RecordingSession.prepareDraft()` leaves a pre-recording draft
    /// in, so this shell is later importable (`AudioTab`) exactly like one.
    private func saveBareMeeting(kind: MeetingKind) async throws {
        guard let policy = environment.defaultPolicy else {
            throw AddAgendaItemError.noWorkspace
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.clock.now()
        let recurrenceRuleID = try await resolveRecurrenceRuleID(workspaceID: policy.workspaceID, now: now)
        if let existing = existingMeeting {
            var updated = existing
            updated.title = trimmedTitle
            updated.startedAt = start
            updated.colorSlot = colorSlot
            updated.kind = kind
            updated.recurrenceRuleID = recurrenceRuleID
            try await environment.meetingRepository.update(updated, at: now)
            if let selectedProjectID {
                try? await environment.projectRepository.setProjects(
                    for: updated.meetingID, projectIDs: [selectedProjectID])
            }
        } else {
            // `endedAt` stays nil — nothing has actually ended yet. Once
            // `start` passes with no recording, the agenda row's own state
            // derivation (`DashboardComposer.rowState`, `end = endedAt ??
            // startedAt`) reads this as `.past` rather than fabricating a
            // "live" window nothing backs.
            let meeting = Meeting(
                meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID, title: trimmedTitle,
                captureMode: .import, originDeviceID: environment.deviceID, startedAt: start, lifecycleState: .ready,
                policyID: policy.policyID, processingMode: policy.defaultProcessingMode, availability: .complete,
                colorSlot: colorSlot, kind: kind, recurrenceRuleID: recurrenceRuleID, createdAt: now, updatedAt: now)
            try await environment.meetingRepository.insert(meeting, at: now)
            if let selectedProjectID {
                try? await environment.projectRepository.setProjects(
                    for: meeting.meetingID, projectIDs: [selectedProjectID])
            }
        }
    }

    /// A due-dated, no-meeting `Action` — the collapsed home for "Action
    /// Reminder" ("The Spine" recommendation, 2026-08-22). No evidence:
    /// this is a direct human assertion, not an AI-extracted claim,
    /// matching `ActionComposerView`'s own reasoning for manually-created
    /// actions (Invariant I4 doesn't apply).
    private func saveReminderAction() async throws {
        guard let selfPersonID = environment.selfPersonID, let workspaceID = environment.defaultPolicy?.workspaceID
        else {
            throw AddAgendaItemError.noWorkspace
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = environment.clock.now()
        if let existing = existingReminderAction {
            var updated = existing
            updated.text = trimmedTitle
            updated.date = .explicit(start)
            try await environment.actionRepository.update(updated, at: now)
        } else {
            let action = Action(
                actionID: .generate(clock: environment.clock), workspaceID: workspaceID, text: trimmedTitle,
                date: .explicit(start), evidence: [], createdBy: selfPersonID,
                auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: now)])
            try await environment.actionRepository.insert(action, at: now)
        }
    }
}
