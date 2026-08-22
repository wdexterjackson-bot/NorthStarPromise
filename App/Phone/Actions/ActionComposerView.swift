import NSPCore
import NSPDesignSystem
import SwiftUI

/// Add sheet for a manually-created `Action` — meeting-scoped (`meetingID`
/// set, from `ActionsTab`) or freestanding (`meetingID: nil`, from a
/// `PersonDetailView` "Add a follow-up"). `evidence` is always `[]`: this
/// action wasn't extracted from a transcript by AI, a human is asserting it
/// directly, so Invariant I4 (every *generated* claim needs evidence)
/// doesn't apply — the same reasoning `NoteComposerView` uses for the
/// `.action` note type.
///
/// The counterparty field is a people picker plus a typed-name fallback
/// that auto-creates a lightweight `Person` the moment you save with an
/// unmatched name (People recommendation, 2026-08-22, decision 2) — there's
/// still no attendee/voice resolution, but assigning a follow-up to someone
/// no longer requires adding them as a Person first.
struct ActionComposerView: View {
    let meetingID: MeetingID?
    let environment: AppEnvironment
    /// Pre-selects and locks the counterparty — set when opened from that
    /// person's own page, so "add a follow-up" doesn't make you re-pick
    /// the person you're already looking at.
    var presetCounterpartyID: PersonID?
    let onSaved: (Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var assignToMe = false
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var people: [Person] = []
    @State private var selectedCounterpartyID: PersonID?
    @State private var newCounterpartyName = ""
    @State private var direction: CommitmentDirection = .iOwe
    @State private var saveError: String?
    @State private var isSaving = false

    private var isLockedToPreset: Bool { presetCounterpartyID != nil }

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
                if !isLockedToPreset {
                    Section("Who's this with") {
                        Picker("Person", selection: $selectedCounterpartyID) {
                            Text("None").tag(PersonID?.none)
                            ForEach(people) { person in
                                Text(person.name).tag(PersonID?.some(person.personID))
                            }
                        }
                        TextField("Or type a new name", text: $newCounterpartyName)
                    }
                }
                if hasCounterparty {
                    Section {
                        Picker("Direction", selection: $direction) {
                            Text("I owe them").tag(CommitmentDirection.iOwe)
                            Text("They owe me").tag(CommitmentDirection.theyOwe)
                        }
                        .pickerStyle(.segmented)
                    }
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
            .task { await loadPeople() }
        }
    }

    private var hasCounterparty: Bool {
        isLockedToPreset || selectedCounterpartyID != nil
            || !newCounterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadPeople() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        people = (try? await environment.personRepository.fetchAll(workspaceID: workspaceID)) ?? []
    }

    /// Resolves the counterparty for save: the locked preset, an explicitly
    /// picked existing `Person`, a case-insensitive name match against the
    /// workspace roster, or — the new part — a lightweight `Person` created
    /// on the spot from whatever name was typed.
    private func resolveCounterparty(workspaceID: WorkspaceID, now: Date) async throws -> PersonID? {
        if let presetCounterpartyID { return presetCounterpartyID }
        if let selectedCounterpartyID { return selectedCounterpartyID }
        let trimmed = newCounterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = people.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing.personID
        }
        let person = Person(personID: PersonID(rawValue: UUID()), workspaceID: workspaceID, name: trimmed)
        try await environment.personRepository.insert(person, at: now)
        return person.personID
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
        do {
            let counterpartyID = try await resolveCounterparty(workspaceID: workspaceID, now: now)
            let action = Action(
                actionID: ActionID(rawValue: UUID()), workspaceID: workspaceID, meetingID: meetingID,
                counterpartyID: counterpartyID, text: text,
                owner: assignToMe ? .explicit(selfPersonID) : .unresolved,
                date: hasDueDate ? .explicit(dueDate) : .unresolved,
                direction: counterpartyID != nil ? direction : .iOwe,
                evidence: [], createdBy: selfPersonID,
                auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: now)])
            try await environment.actionRepository.insert(action, at: now)
            onSaved(action)
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
