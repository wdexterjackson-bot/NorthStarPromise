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
    @State private var isAddingFollowUp = false
    @State private var newTag = ""
    /// Free-text context (People plan phase 2, 2026-08-22) — a local draft
    /// so `notesSection`'s Save button only fires a write when it actually
    /// differs from what's persisted.
    @State private var notesDraft = ""
    @State private var isEditingThreads = false
    @State private var isEditingProjects = false

    private var meetingTitles: [MeetingID: String] {
        Dictionary(
            uniqueKeysWithValues: meetings.map {
                ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
            })
    }

    /// Two signals, merged and deduped: the deliberate one
    /// (`Action.counterpartyID`/`direction` — People recommendation,
    /// 2026-08-22) and the original heuristic (owner resolved to this
    /// person or to `self`, on an action from a shared meeting). Kept both
    /// rather than replacing the heuristic outright — today, nothing in
    /// the AI extraction pipeline sets `counterpartyID` yet, so dropping
    /// the heuristic would silently empty these sections for every action
    /// this app has ever generated.
    private var owedByMeToThem: [Action] {
        let byCounterparty = actions.filter {
            ProjectOpenStatuses.set.contains($0.status) && $0.counterpartyID == personID
                && $0.direction == .iOwe
        }
        let byHeuristic = actions.filter {
            ProjectOpenStatuses.set.contains($0.status) && Self.resolvedOwner($0) == environment.selfPersonID
        }
        return Self.merged(byCounterparty, byHeuristic)
    }

    private var owedByThemToMe: [Action] {
        let byCounterparty = actions.filter {
            ProjectOpenStatuses.set.contains($0.status) && $0.counterpartyID == personID
                && $0.direction == .theyOwe
        }
        let byHeuristic = actions.filter {
            ProjectOpenStatuses.set.contains($0.status) && Self.resolvedOwner($0) == personID
        }
        return Self.merged(byCounterparty, byHeuristic)
    }

    private static func merged(_ lhs: [Action], _ rhs: [Action]) -> [Action] {
        var seen = Set<ActionID>()
        return (lhs + rhs).filter { seen.insert($0.actionID).inserted }
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
                        tagsSection
                        notesSection
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
                Button {
                    isAddingFollowUp = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add a follow-up")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add to Thread", systemImage: "arrow.triangle.branch") { isEditingThreads = true }
                    Button("Add to Project", systemImage: "folder") { isEditingProjects = true }
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
        .sheet(isPresented: $isAddingFollowUp) {
            ActionComposerView(
                meetingID: nil, environment: environment, presetCounterpartyID: personID,
                onSaved: { _ in Task { await load() } })
        }
        .sheet(isPresented: $isEditingThreads) {
            PersonThreadsEditSheet(personID: personID, environment: environment, onDone: {})
        }
        .sheet(isPresented: $isEditingProjects) {
            PersonProjectsEditSheet(personID: personID, environment: environment, onDone: {})
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
    private var tagsSection: some View {
        if let person {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                if !person.tags.isEmpty {
                    FlowTagRow(tags: person.tags, onRemove: { tag in Task { await removeTag(tag) } })
                }
                HStack {
                    TextField("Add a tag — e.g. Direct report", text: $newTag)
                        .font(Typo.ui(13, .medium))
                    Button("Add") { Task { await addTag() } }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            HStack {
                Text("Notes").font(Typo.ui(17, .extrabold))
                Spacer()
                if notesDraft != (person?.notes ?? "") {
                    Button("Save") { Task { await saveNotes() } }.font(Typo.ui(12.5, .semibold))
                }
            }
            TextEditor(text: $notesDraft)
                .font(Typo.ui(13, .medium))
                .frame(minHeight: 70)
                .padding(NSPSpacing.small)
                .background(Palette.fill, in: .rect(cornerRadius: 8, style: .continuous))
        }
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
            notesDraft = loadedPerson.notes ?? ""
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
            loadedActions.append(
                contentsOf: try await environment.actionRepository.fetchAll(counterpartyID: personID))
            meetings = loadedMeetings
            actions = loadedActions
            decisions = loadedDecisions
        } catch {
            loadError = "\(error)"
        }
    }

    private func addTag() async {
        guard var person else { return }
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !person.tags.contains(trimmed) else { return }
        person.tags.append(trimmed)
        do {
            try await environment.personRepository.update(person, at: environment.clock.now())
            self.person = person
            newTag = ""
        } catch {
            loadError = "\(error)"
        }
    }

    private func removeTag(_ tag: String) async {
        guard var person else { return }
        person.tags.removeAll { $0 == tag }
        do {
            try await environment.personRepository.update(person, at: environment.clock.now())
            self.person = person
        } catch {
            loadError = "\(error)"
        }
    }

    private func saveNotes() async {
        guard var person else { return }
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        person.notes = trimmed.isEmpty ? nil : trimmed
        do {
            try await environment.personRepository.update(person, at: environment.clock.now())
            self.person = person
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

/// Every workspace Thread, toggled for this person's membership — the
/// person-side counterpart to `ThreadDetailView`'s `ThreadPeopleEditSheet`
/// (People plan phase 2, 2026-08-22). Saves per-toggle (read-modify-write
/// against that thread's own participant set) rather than batching, since
/// there's no single "set every thread for a person" repository call.
private struct PersonThreadsEditSheet: View {
    let personID: PersonID
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allThreads: [NSPThread] = []
    @State private var memberThreadIDs: Set<NSPThreadID> = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Threads") {
                    if allThreads.isEmpty {
                        Text("No threads yet.").font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
                    } else {
                        ForEach(allThreads.sorted(by: { $0.title < $1.title })) { thread in
                            Toggle(thread.title, isOn: threadBinding(thread.threadID))
                        }
                    }
                }
                if let errorText {
                    Text(errorText).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Add to Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
            .task { await load() }
        }
    }

    private func threadBinding(_ threadID: NSPThreadID) -> Binding<Bool> {
        Binding(get: { memberThreadIDs.contains(threadID) }, set: { isOn in Task { await toggle(threadID, isOn: isOn) } })
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        allThreads = (try? await environment.threadRepository.fetchAll(workspaceID: workspaceID)) ?? []
        memberThreadIDs = (try? await environment.threadParticipantRepository.fetchThreadIDs(for: personID)) ?? []
    }

    private func toggle(_ threadID: NSPThreadID, isOn: Bool) async {
        do {
            var participants = try await environment.threadParticipantRepository.fetchParticipantIDs(for: threadID)
            if isOn { participants.insert(personID) } else { participants.remove(personID) }
            try await environment.threadParticipantRepository.setParticipants(for: threadID, personIDs: participants)
            if isOn { memberThreadIDs.insert(threadID) } else { memberThreadIDs.remove(threadID) }
        } catch {
            errorText = "\(error)"
        }
    }
}

/// Every workspace Project, toggled for this person's membership — mirrors
/// `PersonThreadsEditSheet` (People plan phase 2, 2026-08-22).
private struct PersonProjectsEditSheet: View {
    let personID: PersonID
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allProjects: [Project] = []
    @State private var memberProjectIDs: Set<ProjectID> = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Projects") {
                    if allProjects.isEmpty {
                        Text("No projects yet.").font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
                    } else {
                        ForEach(allProjects.sorted(by: { $0.name < $1.name })) { project in
                            Toggle(project.name, isOn: projectBinding(project.projectID))
                        }
                    }
                }
                if let errorText {
                    Text(errorText).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Add to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
            .task { await load() }
        }
    }

    private func projectBinding(_ projectID: ProjectID) -> Binding<Bool> {
        Binding(
            get: { memberProjectIDs.contains(projectID) }, set: { isOn in Task { await toggle(projectID, isOn: isOn) } }
        )
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        allProjects = (try? await environment.projectRepository.fetchAll(workspaceID: workspaceID)) ?? []
        memberProjectIDs = (try? await environment.projectPersonRepository.fetchProjectIDs(for: personID)) ?? []
    }

    private func toggle(_ projectID: ProjectID, isOn: Bool) async {
        do {
            var members = try await environment.projectPersonRepository.fetchPersonIDs(for: projectID)
            if isOn { members.insert(personID) } else { members.remove(personID) }
            try await environment.projectPersonRepository.setPeople(for: projectID, personIDs: members)
            if isOn { memberProjectIDs.insert(projectID) } else { memberProjectIDs.remove(projectID) }
        } catch {
            errorText = "\(error)"
        }
    }
}

/// A person's freeform relationship tags, tap-to-remove — horizontally
/// scrolling rather than a true wrap layout, since the tag count here is
/// always small (People recommendation, 2026-08-22: freeform, not a fixed
/// taxonomy, so nothing bounds it structurally, but in practice this is a
/// handful of labels, not a paragraph).
private struct FlowTagRow: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        onRemove(tag)
                    } label: {
                        HStack(spacing: 4) {
                            Text(tag).font(Typo.ui(11.5, .semibold))
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.fill, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(tag)")
                }
            }
        }
    }
}
