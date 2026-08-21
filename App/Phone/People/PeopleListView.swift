import NSPCore
import NSPDesignSystem
import SwiftUI

/// The list of active people you're meeting with (docs/07's meeting
/// organizer functionality) — `self` (`AppEnvironment.selfPersonID`, "You")
/// is excluded, since seeing yourself in your own contacts list would be
/// odd; it still exists in the same `person` table for owner comparisons
/// elsewhere (`PersonDetailView`'s "what you owe them" split).
@MainActor
struct PeopleListView: View {
    let environment: AppEnvironment
    /// iPad only — see `TodayView.onSelectMeeting`'s doc comment for the
    /// full reasoning this pattern follows everywhere else.
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var people: [Person] = []
    @State private var meetingCounts: [PersonID: Int] = [:]
    @State private var loadError: String?
    @State private var isShowingNewPerson = false

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load people", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if people.isEmpty {
                    ContentUnavailableView(
                        "No people yet", systemImage: "person.2",
                        description: Text(
                            "Add attendees from a meeting's Overview tab, or add someone here directly."))
                } else {
                    List {
                        ForEach(people) { person in
                            NavigationLink(value: person.personID) {
                                PersonRow(person: person, meetingCount: meetingCounts[person.personID] ?? 0)
                            }
                        }
                    }
                }
            }
            .navigationTitle("People")
            .navigationDestination(for: PersonID.self) { personID in
                PersonDetailView(personID: personID, environment: environment, onSelectMeeting: onSelectMeeting)
            }
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Person", systemImage: "plus") { isShowingNewPerson = true }
                }
            }
            .sheet(isPresented: $isShowingNewPerson) {
                NewPersonSheet(environment: environment, onDone: { Task { await load() } })
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            let fetched = try await environment.personRepository.fetchAll(workspaceID: workspaceID)
            people = fetched.filter { $0.personID != environment.selfPersonID }
            var counts: [PersonID: Int] = [:]
            for person in people {
                counts[person.personID] = try await environment.meetingAttendeeRepository.fetchMeetingIDs(
                    for: person.personID
                ).count
            }
            meetingCounts = counts
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct PersonRow: View {
    let person: Person
    let meetingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
            Text(person.name).font(Typo.ui(14.5, .bold)).foregroundStyle(Palette.textPrimary)
            Text("\(meetingCount) meeting\(meetingCount == 1 ? "" : "s")")
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// Add a person directly (rather than only via a meeting's attendee list)
/// — following `NewProjectSheet`'s exact shape.
private struct NewPersonSheet: View {
    let environment: AppEnvironment
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                }
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        isSaving = true
        defer { isSaving = false }

        let person = Person(
            personID: PersonID(rawValue: UUID()), workspaceID: workspaceID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await environment.personRepository.insert(person, at: environment.clock.now())
            onDone()
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
