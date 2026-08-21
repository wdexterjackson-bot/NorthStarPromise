import NSPCore
import NSPDesignSystem
import SwiftUI

/// Everything relevant across every meeting shared with one person: what
/// you owe them, what they owe you (both derived from `Action.owner` on
/// meetings they attended — `meeting_attendee`), recent decisions
/// (`Decision`, attributed the same way, ordered by their meeting's date),
/// and next steps (open actions from shared meetings with no owner
/// resolved yet).
@MainActor
struct PersonDetailView: View {
    let personID: PersonID
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var person: Person?
    @State private var meetings: [Meeting] = []
    @State private var actions: [Action] = []
    @State private var decisions: [Decision] = []
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var renamedName = ""
    @State private var isConfirmingDelete = false

    private var meetingTitles: [MeetingID: String] {
        Dictionary(
            uniqueKeysWithValues: meetings.map {
                ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
            })
    }

    private var owedByMeToThem: [Action] {
        actions.filter {
            ProjectOpenStatuses.set.contains($0.status) && Self.resolvedOwner($0) == environment.selfPersonID
        }
    }

    private var owedByThemToMe: [Action] {
        actions.filter { ProjectOpenStatuses.set.contains($0.status) && Self.resolvedOwner($0) == personID }
    }

    private var nextSteps: [Action] {
        actions.filter { ProjectOpenStatuses.set.contains($0.status) && Self.resolvedOwner($0) == nil }
    }

    /// Newest meeting first — `Decision` carries no timestamp of its own,
    /// so "recent" is derived from the meeting it came from.
    private var recentDecisions: [Decision] {
        decisions.sorted { lhs, rhs in
            let lhsDate = meetings.first { $0.meetingID == lhs.meetingID }?.startedAt ?? .distantPast
            let rhsDate = meetings.first { $0.meetingID == rhs.meetingID }?.startedAt ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load this person", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if person != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                        meetingsSection
                        actionSection(title: "What You Owe Them", actions: owedByMeToThem)
                        actionSection(title: "What They Owe You", actions: owedByThemToMe)
                        decisionsSection
                        actionSection(title: "Next Steps", actions: nextSteps)
                    }
                    .padding(NSPSpacing.large)
                }
                .background(Palette.canvas)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(person?.name ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename") {
                        renamedName = person?.name ?? ""
                        isRenaming = true
                    }
                    Button("Delete Person", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Person", isPresented: $isRenaming) {
            TextField("Name", text: $renamedName)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this person?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Person", role: .destructive) { Task { await deletePerson() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Meetings stay untouched — only this person's own record is removed. Can't be undone.")
        }
        .task { await load() }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Meetings").font(Typo.ui(17, .extrabold))
            if meetings.isEmpty {
                Text("Add this person as an attendee from a meeting's Overview tab.")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(meetings.sorted(by: { $0.startedAt > $1.startedAt })) { meeting in
                    dashboardMeetingLink(meeting.meetingID, onSelectMeeting: onSelectMeeting) {
                        MeetingRow(meeting: meeting).nspCard()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(title: String, actions: [Action]) -> some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text(title).font(Typo.ui(17, .extrabold))
                ForEach(actions) { action in
                    dashboardMeetingLink(action.meetingID, onSelectMeeting: onSelectMeeting) {
                        DashboardActionRow(
                            action: action,
                            meetingTitle: action.meetingID.flatMap { meetingTitles[$0] }
                                ?? (action.meetingID == nil ? "Personal" : "Untitled meeting"),
                            isOverdue: Self.isOverdue(action, now: environment.clock.now()))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var decisionsSection: some View {
        if !recentDecisions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Recent Decisions").font(Typo.ui(17, .extrabold))
                ForEach(recentDecisions) { decision in
                    dashboardMeetingLink(decision.meetingID, onSelectMeeting: onSelectMeeting) {
                        VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                            Text(decision.text).font(Typo.ui(14, .semibold))
                            Text(meetingTitles[decision.meetingID] ?? "Untitled meeting")
                                .font(Typo.ui(11.5, .medium))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nspCard()
                    }
                }
            }
        }
    }

    private static func resolvedOwner(_ action: Action) -> PersonID? {
        switch action.owner {
        case .explicit(let id), .inferred(let id): return id
        case .unresolved: return nil
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
            guard let loadedPerson = try await environment.personRepository.find(personID) else {
                loadError = "This person no longer exists."
                return
            }
            person = loadedPerson
            let meetingIDs = try await environment.meetingAttendeeRepository.fetchMeetingIDs(for: personID)
            var loadedMeetings: [Meeting] = []
            var loadedActions: [Action] = []
            var loadedDecisions: [Decision] = []
            for meetingID in meetingIDs {
                if let meeting = try await environment.meetingRepository.find(meetingID) {
                    loadedMeetings.append(meeting)
                }
                loadedActions.append(contentsOf: try await environment.actionRepository.fetchAll(meetingID: meetingID))
                loadedDecisions.append(
                    contentsOf: try await environment.decisionRepository.fetchAll(meetingID: meetingID))
            }
            meetings = loadedMeetings
            actions = loadedActions
            decisions = loadedDecisions
        } catch {
            loadError = "\(error)"
        }
    }

    private func rename() async {
        guard var person else { return }
        let trimmed = renamedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        person.name = trimmed
        do {
            try await environment.personRepository.update(person, at: environment.clock.now())
            self.person = person
        } catch {
            loadError = "\(error)"
        }
    }

    private func deletePerson() async {
        do {
            try await environment.personRepository.delete(personID)
            dismiss()
        } catch {
            loadError = "\(error)"
        }
    }
}
