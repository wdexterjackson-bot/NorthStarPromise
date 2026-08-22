import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// Storylines the user and team are working to accomplish — an account, a
/// deal, an initiative, a recurring forum, or a specific 1:1 relationship
/// (`NSPThread`'s own doc comment). Each meeting joins zero or one thread
/// directly; a thread no longer spans multiple `Project`s the way the old
/// `ThreadInMotion` did. Created manually, or accepted from a system
/// suggestion (`ThreadSuggestionEngine`'s own doc comment) — never created
/// automatically without the user reviewing it first.
@MainActor
struct ThreadsListView: View {
    let environment: AppEnvironment
    /// iPad only — see `TodayView.onSelectMeeting`'s doc comment for the
    /// full reasoning this pattern follows everywhere else.
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var threads: [NSPThread] = []
    @State private var suggestions: [SuggestedThread] = []
    @State private var loadError: String?
    @State private var isShowingNewThread = false

    private var openThreads: [NSPThread] { threads.filter { $0.status != .closed } }
    private var closedThreads: [NSPThread] { threads.filter { $0.status == .closed } }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load threads", systemImage: "exclamationmark.triangle", description: Text(loadError)
                    )
                } else if threads.isEmpty && suggestions.isEmpty {
                    ContentUnavailableView(
                        "No threads in motion yet", systemImage: "arrow.triangle.branch",
                        description: Text("Create a thread to track an account, deal, or initiative over time."))
                } else {
                    threadsList
                }
            }
            .navigationTitle("Threads")
            .navigationDestination(for: NSPThreadID.self) { threadID in
                ThreadDetailView(threadID: threadID, environment: environment, onSelectMeeting: onSelectMeeting)
            }
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Thread", systemImage: "plus") { isShowingNewThread = true }
                }
            }
            .sheet(isPresented: $isShowingNewThread) {
                NewThreadSheet(environment: environment, onDone: { Task { await load() } })
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var threadsList: some View {
        List {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        SuggestedThreadRow(
                            suggestion: suggestion, onAccept: { Task { await acceptSuggestion(suggestion) } },
                            onDismiss: { Task { await dismissSuggestion(suggestion) } })
                    }
                } header: {
                    Text("Suggested")
                } footer: {
                    Text(
                        "Grouped automatically from similar open action items, insights, and decisions across meetings."
                    )
                }
            }
            if !openThreads.isEmpty {
                Section("In Motion") {
                    ForEach(openThreads) { thread in
                        NavigationLink(value: thread.threadID) { ThreadRow(thread: thread) }
                    }
                }
            }
            if !closedThreads.isEmpty {
                Section("Closed") {
                    ForEach(closedThreads) { thread in
                        NavigationLink(value: thread.threadID) { ThreadRow(thread: thread) }
                    }
                }
            }
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        threads = (try? await environment.threadRepository.fetchAll(workspaceID: workspaceID)) ?? []
        await loadSuggestions(workspaceID: workspaceID)
    }

    /// Recomputes suggestions from every open action item, insight, and
    /// decision across the workspace's meetings — best-effort (`try?`
    /// throughout): a suggestion is a nice-to-have, never something a
    /// failure here should turn into a visible error over the real thread
    /// list above.
    private func loadSuggestions(workspaceID: WorkspaceID) async {
        guard
            let meetings = try? await environment.meetingRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
        else { return }

        var openActions: [Action] = []
        var insights: [Insight] = []
        var decisions: [Decision] = []
        for meeting in meetings {
            openActions.append(
                contentsOf: (try? await environment.actionRepository.fetchAll(meetingID: meeting.meetingID))?
                    .filter { ProjectOpenStatuses.set.contains($0.status) } ?? [])
            insights.append(
                contentsOf: (try? await environment.insightRepository.fetchAll(meetingID: meeting.meetingID)) ?? [])
            decisions.append(
                contentsOf: (try? await environment.decisionRepository.fetchAll(meetingID: meeting.meetingID)) ?? [])
        }

        // Every thread's current meeting set, via the `meeting_thread`
        // join table (a meeting may now belong to several threads at once).
        let meetingIDsByThread =
            (try? await environment.threadRepository.fetchMeetingIDsByThread(workspaceID: workspaceID)) ?? [:]
        let existingMeetingSets = meetingIDsByThread.values.filter { !$0.isEmpty }
        let dismissed =
            (try? await environment.threadSuggestionDismissalRepository.fetchDismissedFingerprints(
                workspaceID: workspaceID)) ?? []

        let sources = ThreadSuggestionEngine.SignalSources(
            actions: openActions, insights: insights, decisions: decisions)
        suggestions =
            (try? await ThreadSuggestionEngine.suggest(
                sources, embedder: environment.embedder, existingThreadMeetingSets: existingMeetingSets,
                dismissedFingerprints: dismissed)) ?? []
    }

    private func acceptSuggestion(_ suggestion: SuggestedThread) async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        let now = environment.clock.now()
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID, title: suggestion.suggestedTitle,
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        do {
            try await environment.threadRepository.insert(thread, at: now)
            try await environment.threadRepository.setMeetings(
                for: thread.threadID, meetingIDs: suggestion.meetingIDs)
            suggestions.removeAll { $0.id == suggestion.id }
            await load()
        } catch {
            loadError = "\(error)"
        }
    }

    private func dismissSuggestion(_ suggestion: SuggestedThread) async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            try await environment.threadSuggestionDismissalRepository.dismiss(
                fingerprint: suggestion.fingerprint, workspaceID: workspaceID, at: environment.clock.now())
            suggestions.removeAll { $0.id == suggestion.id }
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct ThreadRow: View {
    let thread: NSPThread

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            ThreadDot(color: Palette.threadSlots[thread.colorSlot])
            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(thread.title).font(Typo.ui(14, .bold))
                if let description = thread.threadDescription, !description.isEmpty {
                    Text(description).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary).lineLimit(2)
                }
            }
        }
    }
}

private struct SuggestedThreadRow: View {
    let suggestion: SuggestedThread
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            Text(suggestion.suggestedTitle).font(Typo.ui(14, .bold)).lineLimit(2)
            Text("Spans \(suggestion.meetingIDs.count) meetings")
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)
            HStack(spacing: NSPSpacing.medium) {
                Button("Create Thread", action: onAccept).buttonStyle(.borderedProminent).controlSize(.small)
                Button("Dismiss", role: .destructive, action: onDismiss).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, NSPSpacing.extraSmall)
    }
}

private struct NewThreadSheet: View {
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var kind: ThreadKind = .initiative
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Thread") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                    Picker("Kind", selection: $kind) {
                        ForEach(ThreadKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("New Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: UUID()), workspaceID: workspaceID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            threadDescription: trimmedDescription.isEmpty ? nil : trimmedDescription, kind: kind, lastTouchedAt: now,
            createdAt: now, updatedAt: now)

        do {
            try await environment.threadRepository.insert(thread, at: now)
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}

extension ThreadKind {
    var displayName: String {
        switch self {
        case .account: return "Account"
        case .deal: return "Deal"
        case .initiative: return "Initiative"
        case .recurring: return "Recurring"
        case .oneOnOne: return "1:1"
        case .household: return "Household"
        }
    }
}
