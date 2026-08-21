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
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var renamedTitle = ""
    @State private var isConfirmingDelete = false

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
        .task { await load() }
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
