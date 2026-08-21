import NSPCore
import NSPDesignSystem
import SwiftUI

/// One thread's aggregated view — every meeting joined to it via the
/// `meeting_thread` table (a meeting may belong to several threads at
/// once), plus the insights/decisions/open actions those meetings carry,
/// plus any action/decision tagged with this thread directly even without
/// one of those meetings (`NSPThread`'s own doc comment: a thread is most
/// closely related to what was learned and committed to, not the raw
/// recordings themselves). No longer links to `Project`s — the two are
/// independent groupings.
@MainActor
struct ThreadDetailView: View {
    let threadID: NSPThreadID
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var thread: NSPThread?
    @State private var meetings: [Meeting] = []
    @State private var actions: [Action] = []
    @State private var decisions: [Decision] = []
    @State private var insights: [Insight] = []
    @State private var loadError: String?
    @State private var isEditingMeetings = false
    @State private var isRenaming = false
    @State private var renamedTitle = ""
    @State private var isConfirmingDelete = false

    private var openActions: [Action] { actions.filter { ProjectOpenStatuses.set.contains($0.status) } }

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
                    "Couldn't load thread", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let thread {
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                        header(for: thread)
                        meetingsSection
                        actionsSection
                        decisionsSection
                        insightsSection
                    }
                    .padding(NSPSpacing.large)
                }
                .background(Palette.canvas)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(thread?.title ?? "Thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Meetings", systemImage: "link") { isEditingMeetings = true }
                    Button("Rename") {
                        renamedTitle = thread?.title ?? ""
                        isRenaming = true
                    }
                    Button("Delete Thread", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Thread", isPresented: $isRenaming) {
            TextField("Title", text: $renamedTitle)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this thread?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Thread", role: .destructive) { Task { await deleteThread() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Meetings stay untouched — only this thread's grouping is removed. Can't be undone.")
        }
        .sheet(isPresented: $isEditingMeetings) {
            ThreadMeetingsEditSheet(threadID: threadID, environment: environment, onDone: { Task { await load() } })
        }
        .task { await load() }
    }

    @ViewBuilder
    private func header(for thread: NSPThread) -> some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            HStack(spacing: NSPSpacing.small) {
                ThreadDot(color: Palette.threadSlots[thread.colorSlot])
                Text(thread.kind.displayName).font(Typo.ui(11.5, .bold)).foregroundStyle(Palette.textTertiary)
            }
            if let description = thread.threadDescription, !description.isEmpty {
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
            Text("Meetings").font(Typo.ui(17, .extrabold))
            if meetings.isEmpty {
                Text("Link a meeting from Edit Meetings above.")
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
    private var actionsSection: some View {
        if !openActions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Open Action Items").font(Typo.ui(17, .extrabold))
                ForEach(openActions) { action in
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
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Decisions").font(Typo.ui(17, .extrabold))
                ForEach(decisions) { decision in
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

    @ViewBuilder
    private var insightsSection: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Insights").font(Typo.ui(17, .extrabold))
                ForEach(insights) { insight in
                    dashboardMeetingLink(insight.meetingID, onSelectMeeting: onSelectMeeting) {
                        VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                            Text(insight.text).font(Typo.ui(14, .semibold))
                            Text(meetingTitles[insight.meetingID] ?? "Untitled meeting")
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

    private static func isOverdue(_ action: Action, now: Date) -> Bool {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date < now
        case .unresolved: return false
        }
    }

    private func load() async {
        do {
            guard let loadedThread = try await environment.threadRepository.find(threadID) else {
                loadError = "This thread no longer exists."
                return
            }
            thread = loadedThread
            let loadedMeetings = try await environment.meetingRepository.fetchAll(threadID: threadID)
            meetings = loadedMeetings

            var loadedActions: [Action] = []
            var loadedDecisions: [Decision] = []
            var loadedInsights: [Insight] = []
            for meeting in loadedMeetings {
                loadedActions.append(
                    contentsOf: try await environment.actionRepository.fetchAll(meetingID: meeting.meetingID))
                loadedDecisions.append(
                    contentsOf: try await environment.decisionRepository.fetchAll(meetingID: meeting.meetingID))
                loadedInsights.append(
                    contentsOf: try await environment.insightRepository.fetchAll(meetingID: meeting.meetingID))
            }
            try await mergeThreadTaggedCommitments(into: &loadedActions, &loadedDecisions, thread: loadedThread)
            actions = loadedActions
            decisions = loadedDecisions
            insights = loadedInsights
        } catch {
            loadError = "\(error)"
        }
    }

    /// Adds any action/decision tagged `threadID` directly (`Action
    /// .threadID`/`Decision.threadID`), including a freestanding action
    /// with no meeting at all — merged in rather than replacing the
    /// meeting-derived lists above, and deduped by id, since a
    /// meeting-tied commitment can carry the same thread its meeting
    /// already belongs to.
    private func mergeThreadTaggedCommitments(
        into actions: inout [Action], _ decisions: inout [Decision], thread: NSPThread
    ) async throws {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        let knownActionIDs = Set(actions.map(\.actionID))
        let knownDecisionIDs = Set(decisions.map(\.decisionID))
        let taggedActions = try await environment.actionRepository.fetchAll(workspaceID: workspaceID)
            .filter { $0.threadID == thread.threadID && !knownActionIDs.contains($0.actionID) }
        let taggedDecisions = try await environment.decisionRepository.fetchAll(workspaceID: workspaceID)
            .filter { $0.threadID == thread.threadID && !knownDecisionIDs.contains($0.decisionID) }
        actions.append(contentsOf: taggedActions)
        decisions.append(contentsOf: taggedDecisions)
    }

    private func rename() async {
        guard var thread else { return }
        let trimmed = renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        thread.title = trimmed
        do {
            try await environment.threadRepository.update(thread, at: environment.clock.now())
            self.thread = thread
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteThread() async {
        do {
            try await environment.threadRepository.delete(threadID)
            dismiss()
        } catch {
            loadError = "\(error)"
        }
    }
}

/// Picks which meetings join this thread — a plain multi-select over the
/// workspace's meetings, backed by `NSPThreadRepository.setMeetings(for:
/// meetingIDs:)`, which replaces this thread's entire meeting membership in
/// one call. A meeting may belong to several threads at once, so checking
/// one here never affects any other thread it's already part of.
private struct ThreadMeetingsEditSheet: View {
    let threadID: NSPThreadID
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allMeetings: [Meeting] = []
    @State private var selectedMeetingIDs: Set<MeetingID> = []
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meetings") {
                    if allMeetings.isEmpty {
                        Text("No meetings yet.").font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
                    } else {
                        ForEach(allMeetings.sorted(by: { $0.startedAt > $1.startedAt })) { meeting in
                            Toggle(
                                meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title,
                                isOn: meetingBinding(meeting.meetingID))
                        }
                    }
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Edit Meetings")
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

    private func meetingBinding(_ meetingID: MeetingID) -> Binding<Bool> {
        Binding(
            get: { selectedMeetingIDs.contains(meetingID) },
            set: { isOn in
                if isOn { selectedMeetingIDs.insert(meetingID) } else { selectedMeetingIDs.remove(meetingID) }
            })
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        allMeetings =
            (try? await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)) ?? []
        let linked = (try? await environment.meetingRepository.fetchAll(threadID: threadID)) ?? []
        selectedMeetingIDs = Set(linked.map(\.meetingID))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.threadRepository.setMeetings(for: threadID, meetingIDs: selectedMeetingIDs)
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
