import NSPCore
import NSPDesignSystem
import SwiftUI

/// The I6 gate for the one status transition that claims something leaves
/// the device: `.confirmed → .sent`. `Settings → Integrations` has nothing
/// configured in this build (no Slack/email/CRM connector exists yet), so
/// this can't actually deliver anywhere — it asks for a destination as a
/// plain label and, on confirm, only changes local status and appends an
/// audit entry. The gate itself (show the exact payload, require an
/// explicit tap, record who confirmed and when) is real; the delivery
/// behind it is not, and the copy says so rather than implying otherwise.
struct SendConfirmationView: View {
    let action: Action
    let environment: AppEnvironment
    let onConfirmed: (Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Payload") {
                    LabeledContent("Action", value: action.text)
                    LabeledContent("Owner", value: ownerLabel)
                    LabeledContent("Due", value: dueLabel)
                }
                Section("Destination") {
                    TextField("e.g. Slack #team-eng", text: $destination)
                    Text(
                        "No integrations are connected yet (Settings → Integrations). Confirming records this "
                            + "as sent — it doesn't deliver anywhere."
                    )
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Palette.textTertiary)
                }
            }
            .navigationTitle("Confirm Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm & Mark Sent") { confirm() }
                        .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var ownerLabel: String {
        switch action.owner {
        case .explicit, .inferred: return "Assigned"
        case .unresolved: return "Unassigned"
        }
    }

    private var dueLabel: String {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .unresolved: return "No due date"
        }
    }

    private func confirm() {
        guard let actorID = environment.selfPersonID else { return }
        var updated = action
        updated.status = .sent
        updated.destination = destination
        updated.auditTrail.append(
            AuditEntry(
                actorID: actorID, action: "sent", at: environment.clock.now(),
                detail: "destination: \(destination)"))
        onConfirmed(updated)
        Task {
            try? await environment.actionRepository.update(updated, at: environment.clock.now())
        }
        dismiss()
    }
}
