import NSPCore
import NSPDesignSystem
import SwiftUI

/// Shared presentation and transition logic for the per-meeting Actions
/// ledger (`ActionsTab`) and the global Actions dashboard (`ActionsView`) —
/// one place for "what does this status look like" and "what can it become
/// next" so the two screens can't drift apart.
extension ActionStatus {
    var displayName: String {
        switch self {
        case .proposed: return "Proposed"
        case .confirmed: return "Confirmed"
        case .sent: return "Sent"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        }
    }

    var symbolName: String {
        switch self {
        case .proposed: return "circle.dashed"
        case .confirmed: return "checkmark.circle"
        case .sent: return "paperplane.fill"
        case .inProgress: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .proposed: return Palette.textSecondary
        case .confirmed: return Palette.accent.foreground
        case .sent: return Palette.accent.foreground
        case .inProgress: return Palette.warn.foreground
        case .done: return Palette.success.foreground
        case .dismissed: return Palette.textSecondary
        }
    }
}

/// One legal move out of a status, with the verb a menu shows for it.
/// `.dismissed → .proposed` ("Reopen") is the one non-obvious entry — every
/// other terminal-looking status still has a way forward, matching
/// `RecordingSession.dismissFailure()`'s "never leave a dead end" rule
/// (docs/07 §11).
struct ActionTransition: Identifiable {
    let target: ActionStatus
    let label: String
    let symbolName: String
    let isDestructive: Bool

    var id: String { target.rawValue }

    static func available(from status: ActionStatus) -> [ActionTransition] {
        switch status {
        case .proposed:
            return [
                ActionTransition(
                    target: .confirmed, label: "Confirm", symbolName: "checkmark.circle", isDestructive: false),
                ActionTransition(target: .dismissed, label: "Dismiss", symbolName: "xmark.circle", isDestructive: true),
            ]
        case .confirmed:
            return [
                ActionTransition(target: .sent, label: "Send…", symbolName: "paperplane", isDestructive: false),
                ActionTransition(target: .inProgress, label: "Start", symbolName: "clock", isDestructive: false),
                ActionTransition(target: .dismissed, label: "Dismiss", symbolName: "xmark.circle", isDestructive: true),
            ]
        case .sent:
            return [
                ActionTransition(target: .inProgress, label: "Start", symbolName: "clock", isDestructive: false),
                ActionTransition(
                    target: .done, label: "Mark Done", symbolName: "checkmark.circle.fill", isDestructive: false),
            ]
        case .inProgress:
            return [
                ActionTransition(
                    target: .done, label: "Mark Done", symbolName: "checkmark.circle.fill", isDestructive: false),
                ActionTransition(target: .dismissed, label: "Dismiss", symbolName: "xmark.circle", isDestructive: true),
            ]
        case .done:
            return []
        case .dismissed:
            return [
                ActionTransition(
                    target: .proposed, label: "Reopen", symbolName: "arrow.uturn.backward", isDestructive: false)
            ]
        }
    }
}

/// Applies one transition to an in-memory `Action`, stamping `confirmedBy`
/// on the confirming move and appending an audit entry — pure, so callers
/// own persisting the result via `ActionRepository.update`.
enum ActionTransitionApplier {
    static func apply(_ transition: ActionTransition, to action: Action, actorID: PersonID, now: Date) -> Action {
        var updated = action
        updated.status = transition.target
        if transition.target == .confirmed {
            updated.confirmedBy = actorID
        }
        updated.auditTrail.append(AuditEntry(actorID: actorID, action: transition.target.rawValue, at: now))
        return updated
    }
}

/// A pill menu offering every legal next status for `action`. Shared by
/// both Actions screens so the transition rules live in exactly one place.
struct ActionTransitionMenu: View {
    let action: Action
    let environment: AppEnvironment
    let onSendRequested: (Action) -> Void
    let onChanged: (Action) -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        let transitions = ActionTransition.available(from: action.status)
        if !transitions.isEmpty || onDelete != nil {
            Menu {
                ForEach(transitions) { transition in
                    Button(role: transition.isDestructive ? .destructive : nil) {
                        perform(transition)
                    } label: {
                        Label(transition.label, systemImage: transition.symbolName)
                    }
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func perform(_ transition: ActionTransition) {
        if transition.target == .sent {
            onSendRequested(action)
            return
        }
        guard let actorID = environment.selfPersonID else { return }
        let updated = ActionTransitionApplier.apply(
            transition, to: action, actorID: actorID, now: environment.clock.now())
        onChanged(updated)
        Task {
            try? await environment.actionRepository.update(updated, at: environment.clock.now())
        }
    }
}

/// The status pill + text used on every action row, regardless of which
/// screen renders it.
struct ActionStatusPill: View {
    let status: ActionStatus

    var body: some View {
        NSPStatusBadge(symbolName: status.symbolName, label: status.displayName, tint: status.tint)
    }
}
