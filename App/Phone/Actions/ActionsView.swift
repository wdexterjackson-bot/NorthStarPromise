import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Actions dashboard: grouped by status
/// (`Proposed`/`Confirmed`/`Sent`/`InProgress`/`Done`/`Dismissed`), across
/// every meeting in the workspace. Bulk confirm is real; bulk **send**
/// stays behind the same per-payload `SendConfirmationView` a single send
/// uses — I6 doesn't get a bulk exemption (docs/07 §4).
@MainActor
struct ActionsView: View {
    let environment: AppEnvironment
    /// When set (iPad), tapping an action's row calls this with its
    /// meeting instead of pushing — see `TodayView.onSelectMeeting`'s doc
    /// comment for the full reasoning. `ActionRowCard` itself has no
    /// navigation; this only affects the tap-to-open-meeting affordance
    /// this view wraps each row in below.
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var actions: [Action] = []
    @State private var meetingTitles: [MeetingID: String] = [:]
    @State private var loadError: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<ActionID> = []
    @State private var sendTarget: Action?

    private static let sectionOrder: [ActionStatus] = [.proposed, .confirmed, .sent, .inProgress, .done, .dismissed]

    private func actions(for status: ActionStatus) -> [Action] {
        actions.filter { $0.status == status }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load actions", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if actions.isEmpty {
                    ContentUnavailableView(
                        "No actions yet", systemImage: "checkmark.circle",
                        description: Text(
                            "Actions you add from a meeting's Actions tab appear here, grouped by status."))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                            ForEach(Self.sectionOrder, id: \.self) { status in
                                let sectionActions = actions(for: status)
                                if !sectionActions.isEmpty {
                                    section(for: status, actions: sectionActions)
                                }
                            }
                        }
                        .padding(NSPSpacing.large)
                    }
                }
            }
            .navigationTitle("Actions")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isSelecting {
                        Button("Done") {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    } else if !actions(for: .proposed).isEmpty {
                        Button("Select") { isSelecting = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedIDs.isEmpty {
                    Button {
                        Task { await confirmSelected() }
                    } label: {
                        Text("Confirm \(selectedIDs.count) Selected")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(NSPSpacing.large)
                    .background(.bar)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $sendTarget) { action in
            SendConfirmationView(action: action, environment: environment, onConfirmed: apply)
        }
    }

    @ViewBuilder
    private func section(for status: ActionStatus, actions: [Action]) -> some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Label(status.displayName, systemImage: status.symbolName)
                .font(.headline)
                .foregroundStyle(status.tint)

            ForEach(actions) { action in
                let card = ActionRowCard(
                    action: action, environment: environment, onChanged: apply, onSendRequested: { sendTarget = $0 },
                    onDelete: { Task { await deleteAction(action.actionID) } },
                    showsSelection: isSelecting && status == .proposed,
                    isSelected: selectedIDs.contains(action.actionID),
                    onToggleSelection: { toggleSelection(action.actionID) },
                    meetingTitle: meetingTitles[action.meetingID])
                if isSelecting {
                    card
                } else if let onSelectMeeting {
                    Button {
                        onSelectMeeting(action.meetingID)
                    } label: {
                        card
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: action.meetingID) { card }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleSelection(_ id: ActionID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func apply(_ action: Action) {
        if let index = actions.firstIndex(where: { $0.actionID == action.actionID }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
    }

    private func confirmSelected() async {
        guard let actorID = environment.selfPersonID else { return }
        let now = environment.clock.now()
        for id in selectedIDs {
            guard let action = actions.first(where: { $0.actionID == id }),
                let transition = ActionTransition.available(from: action.status).first(where: {
                    $0.target == .confirmed
                })
            else { continue }
            let updated = ActionTransitionApplier.apply(transition, to: action, actorID: actorID, now: now)
            apply(updated)
            try? await environment.actionRepository.update(updated, at: now)
        }
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func deleteAction(_ id: ActionID) async {
        actions.removeAll { $0.actionID == id }
        do {
            try await environment.actionRepository.delete(id)
        } catch {
            loadError = "\(error)"
            await load()
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            async let fetchedActions = environment.actionRepository.fetchAll(workspaceID: workspaceID)
            async let fetchedMeetings = environment.meetingRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            actions = try await fetchedActions
            meetingTitles = Dictionary(
                uniqueKeysWithValues: try await fetchedMeetings.map {
                    ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
                })
        } catch {
            loadError = "\(error)"
        }
    }
}
