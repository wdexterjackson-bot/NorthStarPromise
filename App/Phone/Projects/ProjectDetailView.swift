import NSPCore
import NSPDesignSystem
import SwiftUI

/// One project's meetings, mental notes, and the open actions those carry
/// — a project has no data of its own beyond a name/description
/// (`Project`'s own doc comment); everything else here is resolved through
/// the `meeting_project` join (`ProjectRepository.fetchMeetingIDs`).
@MainActor
struct ProjectDetailView: View {
    let projectID: ProjectID
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var project: Project?
    @State private var meetings: [Meeting] = []
    @State private var actions: [Action] = []
    /// People tracked against this project (People plan phase 2,
    /// 2026-08-22) — independent of meeting attendance.
    @State private var people: [Person] = []
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var renamedTitle = ""
    @State private var isConfirmingDelete = false
    @State private var isEditingPeople = false

    private var openActions: [Action] {
        actions.filter { ProjectOpenStatuses.set.contains($0.status) }
    }

    private var meetingTitles: [MeetingID: String] {
        Dictionary(
            uniqueKeysWithValues: meetings.map {
                ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
            })
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load project", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                        header(for: project)
                        peopleSection
                        meetingsSection
                        actionsSection
                    }
                    .padding(NSPSpacing.large)
                }
                .background(Palette.canvas)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit People", systemImage: "person.2") { isEditingPeople = true }
                    Button("Rename") {
                        renamedTitle = project?.name ?? ""
                        isRenaming = true
                    }
                    Button("Delete Project", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Project", isPresented: $isRenaming) {
            TextField("Name", text: $renamedTitle)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this project?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) { Task { await deleteProject() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Meetings stay untouched — only the project grouping is removed. Can't be undone.")
        }
        .sheet(isPresented: $isEditingPeople) {
            ProjectPeopleEditSheet(projectID: projectID, environment: environment, onDone: { Task { await load() } })
        }
        .task { await load() }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("People").font(Typo.ui(17, .extrabold))
                FlowPeopleRow(people: people)
            }
        }
    }

    @ViewBuilder
    private func header(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            if let description = project.projectDescription, !description.isEmpty {
                Text(description).font(Typo.ui(14, .medium)).foregroundStyle(Palette.textTertiary)
            }
            HStack(spacing: NSPSpacing.small) {
                Text("\(meetings.count) meeting\(meetings.count == 1 ? "" : "s")")
                Text("·")
                Text("\(openActions.count) open action\(openActions.count == 1 ? "" : "s")")
            }
            .font(Typo.ui(13, .medium))
            .foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Meetings & Notes").font(Typo.ui(17, .extrabold))
            if meetings.isEmpty {
                Text("Assign a meeting or mental note to this project from its title prompt after recording.")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(meetings.sorted(by: { $0.startedAt > $1.startedAt })) { meeting in
                    dashboardMeetingLink(meeting.meetingID, onSelectMeeting: onSelectMeeting) {
                        MeetingRow(meeting: meeting, onDelete: { Task { await deleteMeeting(meeting.meetingID) } })
                            .nspCard()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if !openActions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Open Action Items").font(Typo.ui(17, .extrabold))
                ForEach(openActions) { action in
                    dashboardMeetingLink(action.meetingID, onSelectMeeting: onSelectMeeting) {
                        DashboardActionRow(
                            action: action,
                            meetingTitle: action.meetingID.flatMap { meetingTitles[$0] } ?? "Untitled meeting",
                            isOverdue: Self.isOverdue(action, now: environment.clock.now()))
                    }
                }
            }
        }
    }

    private static func isOverdue(_ action: Action, now: Date) -> Bool {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date < now
        case .unresolved: return false
        }
    }

    private func load() async {
        do {
            guard let loadedProject = try await environment.projectRepository.find(projectID) else {
                loadError = "This project no longer exists."
                return
            }
            project = loadedProject
            let meetingIDs = try await environment.projectRepository.fetchMeetingIDs(for: projectID)
            var loadedMeetings: [Meeting] = []
            var loadedActions: [Action] = []
            for meetingID in meetingIDs {
                if let meeting = try await environment.meetingRepository.find(meetingID) {
                    loadedMeetings.append(meeting)
                }
                loadedActions.append(contentsOf: try await environment.actionRepository.fetchAll(meetingID: meetingID))
            }
            meetings = loadedMeetings
            actions = loadedActions

            let personIDs = try await environment.projectPersonRepository.fetchPersonIDs(for: projectID)
            var loadedPeople: [Person] = []
            for personID in personIDs {
                if let person = try await environment.personRepository.find(personID) { loadedPeople.append(person) }
            }
            people = loadedPeople.sorted { $0.name < $1.name }
        } catch {
            loadError = "\(error)"
        }
    }

    private func rename() async {
        guard var project else { return }
        let trimmed = renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        do {
            try await environment.projectRepository.update(project, at: environment.clock.now())
            self.project = project
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteProject() async {
        do {
            try await environment.projectRepository.delete(projectID)
            dismiss()
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteMeeting(_ meetingID: MeetingID) async {
        do {
            try await environment.deleteMeeting(meetingID)
            await load()
        } catch {
            loadError = "\(error)"
        }
    }
}

/// Mirrors `ThreadDetailView`'s `ThreadPeopleEditSheet` — swap `NSPThreadID`/
/// `threadParticipantRepository` for `ProjectID`/`projectPersonRepository`
/// (People plan phase 2, 2026-08-22).
private struct ProjectPeopleEditSheet: View {
    let projectID: ProjectID
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allPeople: [Person] = []
    @State private var selectedPersonIDs: Set<PersonID> = []
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("People") {
                    if allPeople.isEmpty {
                        Text("No people yet.").font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
                    } else {
                        ForEach(allPeople.sorted(by: { $0.name < $1.name })) { person in
                            Toggle(person.name, isOn: personBinding(person.personID))
                        }
                    }
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Edit People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .task { await load() }
        }
    }

    private func personBinding(_ personID: PersonID) -> Binding<Bool> {
        Binding(
            get: { selectedPersonIDs.contains(personID) },
            set: { isOn in
                if isOn { selectedPersonIDs.insert(personID) } else { selectedPersonIDs.remove(personID) }
            })
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        allPeople = (try? await environment.personRepository.fetchAll(workspaceID: workspaceID)) ?? []
        selectedPersonIDs = (try? await environment.projectPersonRepository.fetchPersonIDs(for: projectID)) ?? []
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.projectPersonRepository.setPeople(for: projectID, personIDs: selectedPersonIDs)
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
