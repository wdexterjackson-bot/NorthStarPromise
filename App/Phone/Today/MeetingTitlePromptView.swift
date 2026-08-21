import NSPCore
import NSPDesignSystem
import SwiftUI

/// Shown once, right after Stop, only when the meeting is still carrying
/// the default `"Untitled meeting"` title (`RecordingSession.stop()`'s
/// `pendingTitleMeeting` gate) — a meeting already titled via the iPad
/// canvas's title band isn't redundantly prompted. This is also where AI
/// processing for the meeting actually starts (`RecordingSession.stop()`'s
/// doc comment explains why it waits this long) — "Save Recording" and
/// "Delete Recording" are the only two ways out, deliberately not a
/// "skip"/"continue" pair: this is the one moment a just-recorded meeting
/// can still be discarded outright rather than merely renamed, so the
/// buttons say exactly what each one does.
struct MeetingTitlePromptView: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let onSave: (Meeting, PostRecordingProcessingOptions) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var options = PostRecordingProcessingOptions()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDelete = false
    @State private var availableProjects: [Project] = []
    @State private var selectedProjectIDs: Set<ProjectID> = []
    @FocusState private var isTitleFocused: Bool

    init(
        meeting: Meeting, environment: AppEnvironment,
        onSave: @escaping (Meeting, PostRecordingProcessingOptions) -> Void, onDelete: @escaping () -> Void
    ) {
        self.meeting = meeting
        self.environment = environment
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this meeting") {
                    TextField("Meeting title", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                Section {
                    Toggle("Generate Meeting Transcript", isOn: $options.generateTranscript)
                    Toggle("Generate Minutes & Notes", isOn: $options.generateMinutes)
                        .disabled(!options.generateTranscript)
                    Toggle("Generate Action Items", isOn: $options.generateActionItems)
                        .disabled(!options.generateTranscript)
                } header: {
                    Text("After this recording")
                } footer: {
                    Text("Minutes and action items need a transcript — turning that off turns these off too.")
                }
                .onChange(of: options.generateTranscript) { _, isOn in
                    // Cascade off, never back on — re-enabling the
                    // transcript shouldn't silently re-opt the user into
                    // steps they'd already turned off before turning this
                    // one off.
                    guard !isOn else { return }
                    options.generateMinutes = false
                    options.generateActionItems = false
                }
                projectSection
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Recording saved")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadProjects() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete Recording", role: .destructive) { isConfirmingDelete = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Recording") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Delete this recording?", isPresented: $isConfirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete Recording", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the recording and everything captured in it. Can't be undone.")
            }
            .onAppear { isTitleFocused = true }
        }
    }

    /// A meeting joins at most one project (`Project`'s own doc comment) —
    /// this prompt only ever shows for a real `Meeting` (a Brain Dump's own
    /// finalize path never sets `pendingTitleMeeting`), so a single
    /// `Picker` is always the right shape here.
    @ViewBuilder
    private var projectSection: some View {
        Section {
            if availableProjects.isEmpty {
                Text("No projects yet — create one from the Projects tab.")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                Picker(
                    "Project",
                    selection: Binding(
                        get: { selectedProjectIDs.first },
                        set: { selectedProjectIDs = $0.map { [$0] } ?? [] })
                ) {
                    Text("None").tag(ProjectID?.none)
                    ForEach(availableProjects) { project in
                        Text(project.name).tag(ProjectID?.some(project.projectID))
                    }
                }
            }
        } header: {
            Text("Project")
        }
    }

    private func loadProjects() async {
        availableProjects = (try? await environment.projectRepository.fetchAll(workspaceID: meeting.workspaceID)) ?? []
        selectedProjectIDs = (try? await environment.projectRepository.fetchProjectIDs(for: meeting.meetingID)) ?? []
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }

        var updated = meeting
        if !trimmed.isEmpty {
            updated.title = trimmed
        }
        do {
            try await environment.meetingRepository.update(updated, at: environment.clock.now())
            try await environment.projectRepository.setProjects(
                for: updated.meetingID, projectIDs: selectedProjectIDs)
            onSave(updated, options)
        } catch {
            saveError = "\(error)"
        }
    }
}
