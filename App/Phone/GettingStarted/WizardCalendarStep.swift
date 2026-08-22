import NSPActions
import NSPDesignSystem
import SwiftUI

/// Step 4 — "your calendar." Read-only: this step never writes to the
/// user's real calendar (`EventKitCalendarEventWriter`, the one path that
/// does, isn't called here). What "import" means is the app's own
/// tracking layer — a `ScheduledRecording` row per checked event, the same
/// entity `CalendarEventPickerView`'s existing single-event import already
/// creates, just multi-select. Declining or having nothing to show never
/// blocks continuing.
struct WizardCalendarStep: View {
    let coordinator: GettingStartedCoordinator

    @State private var accessStatus: CalendarAccessStatus = .notDetermined
    @State private var isLoading = false
    @State private var events: [CalendarEventInfo] = []
    @State private var selectedEventIDs: Set<String> = []
    @State private var projectName = ""
    @State private var hasImported = false

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Mind if I look at your calendar? Not to record anything automatically — just so I know "
                    + "what's coming, and whether any of it is part of something recurring I should group "
                    + "together as a Project.")

            if accessStatus == .authorized {
                content
            } else if isLoading {
                ProgressView()
            } else {
                Button("Look at My Calendar") { Task { await requestAccess() } }
                    .buttonStyle(.borderedProminent)
                Text(
                    "No problem if you'd rather not — I'll pick this up the first time you record something that "
                        + "looks recurring.")
                    .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if events.isEmpty {
            Text("Nothing in the next two weeks.").font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                ForEach(events) { event in
                    Button {
                        if selectedEventIDs.contains(event.identifier) {
                            selectedEventIDs.remove(event.identifier)
                        } else {
                            selectedEventIDs.insert(event.identifier)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedEventIDs.contains(event.identifier) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedEventIDs.contains(event.identifier) ? Palette.accent.foreground : Palette.textQuaternary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title.isEmpty ? "Untitled event" : event.title).font(Typo.ui(13.5, .semibold))
                                Text(event.startDate, style: .date).font(Typo.ui(11, .medium)).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !selectedEventIDs.isEmpty {
                TextField("Group as a Project — e.g. Engineering (optional)", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                Button(hasImported ? "Imported" : "Import Selected") { Task { await importSelected() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasImported)
            }
        }
    }

    private func requestAccess() async {
        isLoading = true
        accessStatus = await coordinator.environment.calendarEventReader.requestAccess()
        if accessStatus == .authorized {
            let now = coordinator.environment.clock.now()
            let window = DateInterval(start: now, end: now.addingTimeInterval(14 * 24 * 3600))
            events = await coordinator.environment.calendarEventReader.upcomingEvents(within: window)
        }
        isLoading = false
    }

    private func importSelected() async {
        let selected = events.filter { selectedEventIDs.contains($0.identifier) }
        await coordinator.importSelectedEvents(selected, projectName: projectName)
        hasImported = true
    }
}
