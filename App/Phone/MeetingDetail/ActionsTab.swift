import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's per-meeting Actions tab: "Proposed/Confirmed ledger for
/// this meeting | Export gate per I6." Real `Action` CRUD against
/// `ActionRepository`, with status transitions gated the same way the
/// global dashboard (`ActionsView`) gates them — `ActionTransitionMenu`
/// and `SendConfirmationView` are shared by both.
@MainActor
struct ActionsTab: View {
    let meeting: Meeting
    let environment: AppEnvironment

    @State private var actions: [Action] = []
    @State private var loadError: String?
    @State private var isShowingComposer = false
    @State private var sendTarget: Action?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            HStack {
                Text("Actions").font(.headline)
                Spacer()
                Button {
                    isShowingComposer = true
                } label: {
                    Label("Add action", systemImage: "plus.circle.fill")
                }
                .disabled(environment.selfPersonID == nil)
            }

            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            } else if actions.isEmpty {
                ContentUnavailableView(
                    "No actions yet", systemImage: "checkmark.circle",
                    description: Text("Actions you add for this meeting appear here."))
            } else {
                VStack(spacing: NSPSpacing.medium) {
                    ForEach(actions.sorted { $0.status.rawValue < $1.status.rawValue }) { action in
                        ActionRowCard(
                            action: action, environment: environment, onChanged: apply,
                            onSendRequested: { sendTarget = $0 },
                            onDelete: { Task { await delete(action) } })
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $isShowingComposer) {
            ActionComposerView(meetingID: meeting.meetingID, environment: environment, onSaved: apply)
        }
        .sheet(item: $sendTarget) { action in
            SendConfirmationView(action: action, environment: environment, onConfirmed: apply)
        }
    }

    private func apply(_ action: Action) {
        if let index = actions.firstIndex(where: { $0.actionID == action.actionID }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
    }

    private func load() async {
        do {
            actions = try await environment.actionRepository.fetchAll(meetingID: meeting.meetingID)
        } catch {
            loadError = "\(error)"
        }
    }

    private func delete(_ action: Action) async {
        do {
            try await environment.actionRepository.delete(action.actionID)
            actions.removeAll { $0.actionID == action.actionID }
        } catch {
            loadError = "\(error)"
        }
    }
}
