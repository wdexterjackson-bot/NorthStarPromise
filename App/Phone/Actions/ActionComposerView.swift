import NSPCore
import NSPDesignSystem
import SwiftUI

/// Add sheet for a manually-created `Action`. There's no attendee/contact
/// resolution built yet (only the one local "You" `Person` exists — see
/// `AppEnvironment.selfPersonID`), so the owner picker only offers
/// "Assign to me" or "Unassigned" rather than a real people picker.
/// `evidence` is always `[]`: this action wasn't extracted from a
/// transcript by AI, a human is asserting it directly, so Invariant I4
/// (every *generated* claim needs evidence) doesn't apply — the same
/// reasoning `NoteComposerView` uses for the `.action` note type.
struct ActionComposerView: View {
    let meetingID: MeetingID
    let environment: AppEnvironment
    let onSaved: (Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var assignToMe = false
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs to happen") {
                    TextField("e.g. Send the recap to the team", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Owner") {
                    Toggle("Assign to me", isOn: $assignToMe)
                }
                Section("Due date") {
                    Toggle("Has a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("New Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let selfPersonID = environment.selfPersonID, let workspaceID = environment.defaultPolicy?.workspaceID
        else {
            saveError = "Setup isn't finished yet — try again in a moment."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let now = environment.clock.now()
        let action = Action(
            actionID: ActionID(rawValue: UUID()), workspaceID: workspaceID, meetingID: meetingID, text: text,
            owner: assignToMe ? .explicit(selfPersonID) : .unresolved,
            date: hasDueDate ? .explicit(dueDate) : .unresolved,
            evidence: [], createdBy: selfPersonID,
            auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: now)])

        do {
            try await environment.actionRepository.insert(action, at: now)
            onSaved(action)
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
