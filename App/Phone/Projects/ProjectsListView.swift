import NSPCore
import NSPDesignSystem
import SwiftUI

/// Groups meetings and mental notes around an initiative (`Project`'s own
/// doc comment) — the real feature behind `DashboardView`'s "Projects"
/// section, which links here via `.projects` (`AppTab`'s doc comment).
@MainActor
struct ProjectsListView: View {
    let environment: AppEnvironment
    /// iPad only — see `TodayView.onSelectMeeting`'s doc comment for the
    /// full reasoning this pattern follows everywhere else.
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var projects: [Project] = []
    @State private var meetingCounts: [ProjectID: Int] = [:]
    @State private var openActionCounts: [ProjectID: Int] = [:]
    @State private var loadError: String?
    @State private var isShowingNewProject = false

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load projects", systemImage: "exclamationmark.triangle", description: Text(loadError)
                    )
                } else if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects yet", systemImage: "folder.badge.plus",
                        description: Text(
                            "Create a project to group meetings, mental notes, and action items around one "
                                + "initiative."))
                } else {
                    List {
                        ForEach(projects) { project in
                            NavigationLink(value: project.projectID) {
                                ProjectRow(
                                    project: project, meetingCount: meetingCounts[project.projectID] ?? 0,
                                    openActionCount: openActionCounts[project.projectID] ?? 0)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: ProjectID.self) { projectID in
                ProjectDetailView(projectID: projectID, environment: environment, onSelectMeeting: onSelectMeeting)
            }
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus") { isShowingNewProject = true }
                }
            }
            .sheet(isPresented: $isShowingNewProject) {
                NewProjectSheet(environment: environment, onDone: { Task { await load() } })
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            let fetchedProjects = try await environment.projectRepository.fetchAll(workspaceID: workspaceID)
            projects = fetchedProjects
            var meetingCounts: [ProjectID: Int] = [:]
            var openActionCounts: [ProjectID: Int] = [:]
            for project in fetchedProjects {
                let counts = try await Self.counts(for: project.projectID, environment: environment)
                meetingCounts[project.projectID] = counts.meetings
                openActionCounts[project.projectID] = counts.openActions
            }
            self.meetingCounts = meetingCounts
            self.openActionCounts = openActionCounts
        } catch {
            loadError = "\(error)"
        }
    }

    private static func counts(
        for projectID: ProjectID, environment: AppEnvironment
    ) async throws -> (meetings: Int, openActions: Int) {
        let meetingIDs = try await environment.projectRepository.fetchMeetingIDs(for: projectID)
        var openActionCount = 0
        for meetingID in meetingIDs {
            let actions = try await environment.actionRepository.fetchAll(meetingID: meetingID)
            openActionCount += actions.filter { ProjectOpenStatuses.set.contains($0.status) }.count
        }
        return (meetingIDs.count, openActionCount)
    }
}

/// Shared "what counts as open" definition — `DashboardView` keeps its own
/// copy (`Self.openStatuses`) since it predates this file; not worth a
/// cross-file refactor just to deduplicate one `Set` literal.
enum ProjectOpenStatuses {
    static let set: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]
}

private struct ProjectRow: View {
    let project: Project
    let meetingCount: Int
    let openActionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
            Text(project.name).font(Typo.ui(14, .bold))
            if let description = project.projectDescription, !description.isEmpty {
                Text(description).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary).lineLimit(2)
            }
            HStack(spacing: NSPSpacing.small) {
                Text("\(meetingCount) meeting\(meetingCount == 1 ? "" : "s")")
                if openActionCount > 0 {
                    Text("·")
                    Text("\(openActionCount) open action\(openActionCount == 1 ? "" : "s")")
                }
            }
            .font(Typo.ui(11.5, .medium))
            .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// Create a Project — name and an optional description, following
/// `ScheduleRecordingFormView`'s exact `NavigationStack { Form { ... } }`
/// shape.
private struct NewProjectSheet: View {
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        isSaving = true
        defer { isSaving = false }

        let now = environment.clock.now()
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            projectID: ProjectID(rawValue: UUID()), workspaceID: workspaceID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            projectDescription: trimmedDescription.isEmpty ? nil : trimmedDescription, createdAt: now, updatedAt: now)

        do {
            try await environment.projectRepository.insert(project, at: now)
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
