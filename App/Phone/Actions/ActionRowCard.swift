import NSPCore
import NSPDesignSystem
import SwiftUI

/// One action's card — shared by the per-meeting ledger and the global
/// dashboard so a row looks and behaves identically wherever it appears.
struct ActionRowCard: View {
    let action: Action
    let environment: AppEnvironment
    let onChanged: (Action) -> Void
    let onSendRequested: (Action) -> Void
    var onDelete: (() -> Void)?
    var showsSelection = false
    var isSelected = false
    var onToggleSelection: (() -> Void)?
    /// Shown only by the cross-meeting dashboard, where an action's
    /// meeting isn't otherwise implied by the screen it's on.
    var meetingTitle: String?

    private var dueLabel: String? {
        switch action.date {
        case .explicit(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .inferred(let date): return "\(date.formatted(date: .abbreviated, time: .omitted)) (inferred)"
        case .unresolved: return nil
        }
    }

    private var ownerLabel: String? {
        switch action.owner {
        case .explicit: return "You"
        case .inferred: return "You (inferred)"
        case .unresolved: return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: NSPSpacing.medium) {
            if showsSelection {
                Button {
                    onToggleSelection?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? NSPColor.accent : NSPColor.secondaryText)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            } else {
                NSPIconBadge(symbolName: "checkmark", tint: action.status.tint)
            }

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                if let meetingTitle {
                    Text(meetingTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NSPColor.accent)
                }

                Text(action.text).font(.body.weight(.medium))

                if ownerLabel != nil || dueLabel != nil {
                    HStack(spacing: NSPSpacing.medium) {
                        if let ownerLabel {
                            Label(ownerLabel, systemImage: "person.fill")
                        }
                        if let dueLabel {
                            Label(dueLabel, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(NSPColor.secondaryText)
                }

                ActionStatusPill(status: action.status)
            }

            Spacer(minLength: 0)

            if !showsSelection {
                ActionTransitionMenu(
                    action: action, environment: environment, onSendRequested: onSendRequested, onChanged: onChanged,
                    onDelete: onDelete)
            }
        }
        .nspCard()
    }
}
