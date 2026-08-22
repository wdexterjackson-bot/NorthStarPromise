import NSPCore
import NSPDesignSystem
import SwiftUI

/// "Ask for another quick meeting with the assistant" — reachable from
/// Settings (and My Work's toolbar) any time *after* "The First Hour" has
/// completed once. A deliberately different shape from the first-run
/// wizard: instead of walking through every step in a fixed order, it
/// opens with a topic checklist ("What would you like to go over?") and
/// only asks about what's checked. Reuses the exact same step views and
/// the exact same `GettingStartedCoordinator` write methods as the
/// first-run wizard — same data, same commits-immediately behavior — just
/// a different entry sequence.
struct FollowUpWizardView: View {
    let environment: AppEnvironment
    var onDone: () -> Void

    enum Topic: CaseIterable, Identifiable {
        case threads, people, calendar, actionItems
        var id: Self { self }

        var title: String {
            switch self {
            case .threads: "Threads"
            case .people: "People"
            case .calendar: "Meetings"
            case .actionItems: "Action Items"
            }
        }
        var symbolName: String {
            switch self {
            case .threads: "arrow.triangle.branch"
            case .people: "person.2.fill"
            case .calendar: "calendar"
            case .actionItems: "checkmark.circle"
            }
        }
        var prompt: String {
            switch self {
            case .threads: "Anything new you're juggling since we last talked?"
            case .people: "Anyone new I should be keeping track of?"
            case .calendar: "Want me to look at your calendar again for anything new?"
            case .actionItems: "Anything I should be tracking as an action item?"
            }
        }
    }

    @State private var selectedTopics: Set<Topic> = []
    @State private var hasStarted = false
    @State private var topicIndex = 0
    @State private var coordinator: GettingStartedCoordinator
    @State private var isShowingActionComposer = false

    init(environment: AppEnvironment, onDone: @escaping () -> Void) {
        self.environment = environment
        self.onDone = onDone
        self._coordinator = State(initialValue: GettingStartedCoordinator(environment: environment))
    }

    private var orderedSelectedTopics: [Topic] {
        Topic.allCases.filter { selectedTopics.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasStarted {
                    topicPicker
                } else {
                    topicFlow
                }
            }
            .navigationTitle("Quick Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDone() }
                }
            }
        }
    }

    private var topicPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NSPSpacing.large) {
                WizardPromptBubble(text: "What would you like to go over? Pick as many as you'd like.")
                VStack(spacing: NSPSpacing.small) {
                    ForEach(Topic.allCases) { topic in
                        Button {
                            if selectedTopics.contains(topic) { selectedTopics.remove(topic) } else { selectedTopics.insert(topic) }
                        } label: {
                            HStack {
                                Image(systemName: topic.symbolName).frame(width: 22)
                                Text(topic.title).font(Typo.ui(14.5, .semibold))
                                Spacer()
                                Image(systemName: selectedTopics.contains(topic) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedTopics.contains(topic) ? Palette.accent.foreground : Palette.textQuaternary)
                            }
                            .padding(NSPSpacing.medium)
                            .background(Palette.canvas, in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Start") {
                    topicIndex = 0
                    hasStarted = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTopics.isEmpty)
            }
            .padding(NSPSpacing.large)
        }
    }

    @ViewBuilder
    private var topicFlow: some View {
        if topicIndex >= orderedSelectedTopics.count {
            VStack(spacing: NSPSpacing.large) {
                WizardPromptBubble(text: "That's everything — thanks for the update.")
                Button("Done") { onDone() }.buttonStyle(.borderedProminent)
            }
            .padding(NSPSpacing.large)
        } else {
            let topic = orderedSelectedTopics[topicIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: NSPSpacing.large) {
                    WizardPromptBubble(text: topic.prompt)
                    topicContent(topic)
                }
                .padding(NSPSpacing.large)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button(topicIndex == orderedSelectedTopics.count - 1 ? "Done" : "Next") { topicIndex += 1 }
                        .buttonStyle(.borderedProminent)
                }
                .padding(NSPSpacing.large)
                .background(Palette.canvas)
            }
        }
    }

    @ViewBuilder
    private func topicContent(_ topic: Topic) -> some View {
        switch topic {
        case .threads: WizardThreadsStep(coordinator: coordinator)
        case .people: WizardPeopleStep(coordinator: coordinator)
        case .calendar: WizardCalendarStep(coordinator: coordinator)
        case .actionItems:
            Button("Add an Action Item") { isShowingActionComposer = true }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $isShowingActionComposer) {
                    ActionComposerView(meetingID: nil, environment: environment, onSaved: { _ in })
                }
        }
    }
}
