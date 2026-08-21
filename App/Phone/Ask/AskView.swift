import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// docs/07 §4: "The scope selector is mandatory and always visible — the
/// query field is disabled until a scope is chosen." Backed for real now by
/// `AskCoordinator` → `HybridRetriever` (FTS5 + on-device embeddings, fused
/// via RRF) → `LiveOnDeviceAskAnswerer` (docs/04 §10.3/§10.4). Tapping a
/// citation pushes straight to that meeting's Transcript tab, seeked and
/// scrolled to the cited turn (`CitationTarget`/`MeetingDetailView
/// .initialSeekTurnID`).
@MainActor
struct AskView: View {
    let environment: AppEnvironment

    @State private var coordinator: AskCoordinator
    @State private var scopeSelection: ScopeSelection?
    @State private var projects: [Project] = []
    @State private var meetingTitles: [MeetingID: String] = [:]
    @State private var queryText = ""

    init(environment: AppEnvironment) {
        self.environment = environment
        self._coordinator = State(initialValue: AskCoordinator(environment: environment))
    }

    private var resolvedScope: AskScope? {
        switch scopeSelection {
        case .workspace: return environment.defaultPolicy.map { .workspace($0.workspaceID) }
        case .project(let projectID): return .projectOrTag(projectID.rawValue.uuidString)
        case nil: return nil
        }
    }

    private var isInputDisabled: Bool {
        scopeSelection == nil || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: NSPSpacing.large) {
                VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                    scopePicker
                    inputRow
                }
                .nspCard()

                ScrollView {
                    resultsArea
                }
            }
            .padding(NSPSpacing.large)
            .background(Palette.canvas)
            .navigationTitle("Ask")
            .navigationDestination(for: CitationTarget.self) { target in
                MeetingDetailView(
                    meetingID: target.meetingID, environment: environment, initialTab: .transcript,
                    initialSeekTurnID: target.turnID)
            }
        }
        .task { await loadProjects() }
    }

    private var scopePicker: some View {
        Picker(
            "Scope",
            selection: Binding(
                get: { scopeSelection },
                set: {
                    scopeSelection = $0
                    coordinator.reset()
                })
        ) {
            Text("Choose a scope").tag(ScopeSelection?.none)
            Text("This workspace").tag(ScopeSelection?.some(.workspace))
            ForEach(projects) { project in
                Text(project.name).tag(ScopeSelection?.some(.project(project.projectID)))
            }
        }
        .pickerStyle(.menu)
    }

    private var inputRow: some View {
        HStack {
            TextField("Ask about your meetings…", text: $queryText)
                .textFieldStyle(.roundedBorder)
                .disabled(scopeSelection == nil)
                .onSubmit { Task { await submit() } }
            Button("Ask") { Task { await submit() } }
                .buttonStyle(.borderedProminent)
                .disabled(isInputDisabled)
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        switch coordinator.state {
        case .idle:
            ContentUnavailableView(
                "Ask about your meetings", systemImage: "bubble.left.and.text.bubble.right",
                description: Text("Choose a scope, then ask something like \"When is the Executive Report due?\""))
        case .asking:
            HStack(spacing: NSPSpacing.medium) {
                ProgressView()
                Text("Thinking…").font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NSPSpacing.large)
        case .failed(let reason):
            ContentUnavailableView("No answer", systemImage: "questionmark.circle", description: Text(reason))
        case .answered(let snapshot):
            AskAnswerCard(snapshot: snapshot, meetingTitles: meetingTitles)
        }
    }

    private func submit() async {
        guard let resolvedScope else { return }
        await coordinator.ask(queryText, scope: resolvedScope)
        await loadMeetingTitles()
    }

    private func loadProjects() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        projects = (try? await environment.projectRepository.fetchAll(workspaceID: workspaceID)) ?? []
    }

    private func loadMeetingTitles() async {
        guard case .answered(let snapshot) = coordinator.state else { return }
        var titles = meetingTitles
        for citation in snapshot.citations where titles[citation.meetingID] == nil {
            guard let meeting = try? await environment.meetingRepository.find(citation.meetingID) else { continue }
            titles[citation.meetingID] =
                meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title
        }
        meetingTitles = titles
    }
}

private enum ScopeSelection: Hashable {
    case workspace
    case project(ProjectID)
}

/// What a citation tap navigates to — `MeetingDetailView`'s own
/// `initialSeekTurnID`/`initialTab` parameters do the actual seeking; this
/// is just the `Hashable` payload `navigationDestination(for:)` needs.
private struct CitationTarget: Hashable {
    let meetingID: MeetingID
    let turnID: TranscriptTurnID?
}

/// The answer plus its cited sources, each a tap-through to the exact
/// transcript turn it came from.
private struct AskAnswerCard: View {
    let snapshot: AskAnswer.Snapshot
    let meetingTitles: [MeetingID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text(snapshot.text).font(Typo.ui(14, .medium))
            if !snapshot.citations.isEmpty {
                VStack(alignment: .leading, spacing: NSPSpacing.small) {
                    Text("Sources").font(Typo.ui(11.5, .bold)).foregroundStyle(Palette.textTertiary)
                    ForEach(Array(snapshot.citations.enumerated()), id: \.offset) { _, citation in
                        NavigationLink(
                            value: CitationTarget(meetingID: citation.meetingID, turnID: citation.turnIDs.first)
                        ) {
                            HStack(spacing: NSPSpacing.small) {
                                Image(systemName: "text.bubble")
                                Text(meetingTitles[citation.meetingID] ?? "Untitled meeting")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(Typo.ui(11.5, .medium)).foregroundStyle(
                                    Palette.textTertiary)
                            }
                            .font(Typo.ui(13, .medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nspCard()
    }
}
