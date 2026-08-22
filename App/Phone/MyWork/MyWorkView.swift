import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The management view "The Spine" recommendation (2026-08-22) calls for
/// alongside Today's Agenda's calendar view: an executive doesn't manage
/// meetings, he manages the ongoing things the meetings are about. One card
/// per open `NSPThread` — its next meeting, its open actions, its people,
/// and how long it's been quiet — all sourced from `RelationshipGraph`
/// rather than a bespoke join, so this screen can never drift from what
/// `PersonDetailView`/`ThreadDetailView` already show for the same thread.
@MainActor
struct MyWorkView: View {
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var cards: [ThreadWorkCard] = []
    @State private var loadError: String?

    struct ThreadWorkCard: Identifiable {
        let thread: NSPThread
        let nextMeeting: Meeting?
        let openActionCount: Int
        let peopleCount: Int
        let quietDays: Int
        var id: NSPThreadID { thread.threadID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load My Work", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing in motion yet", systemImage: "arrow.triangle.branch",
                        description: Text("Open threads you're actively working show up here as cards."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: NSPSpacing.medium)],
                                  spacing: NSPSpacing.medium) {
                            ForEach(cards) { card in
                                NavigationLink {
                                    ThreadDetailView(
                                        threadID: card.thread.threadID, environment: environment,
                                        onSelectMeeting: onSelectMeeting)
                                } label: {
                                    ThreadWorkCardView(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(NSPSpacing.large)
                    }
                    .background(Palette.canvas)
                }
            }
            .navigationTitle("My Work")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        WeeklyBriefView(
                            environment: environment, onSelectThread: nil, onSelectPerson: nil)
                    } label: {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                    .accessibilityLabel("Weekly Brief")
                }
            }
            .task { await load() }
            .onChange(of: environment.contentRevision) { _, _ in Task { await load() } }
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            let threads = try await environment.threadRepository.fetchAll(workspaceID: workspaceID)
            let now = environment.clock.now()
            var built: [ThreadWorkCard] = []
            for thread in threads where thread.status != .closed {
                let bundle = try await RelationshipGraph.everything(
                    tiedToThread: thread.threadID, repositories: environment.relationshipRepositories)
                let nextMeeting = bundle.meetings.filter { $0.startedAt > now }.min { $0.startedAt < $1.startedAt }
                let openCount = bundle.actions.filter { ProjectOpenStatuses.set.contains($0.status) }.count
                let quietDays = max(0, Int(now.timeIntervalSince(thread.lastTouchedAt) / 86400))
                built.append(
                    ThreadWorkCard(
                        thread: thread, nextMeeting: nextMeeting, openActionCount: openCount,
                        peopleCount: bundle.personIDs.count, quietDays: quietDays))
            }
            cards = built.sorted { $0.thread.lastTouchedAt > $1.thread.lastTouchedAt }
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct ThreadWorkCardView: View {
    let card: MyWorkView.ThreadWorkCard

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            HStack(spacing: 8) {
                Circle().fill(Palette.threadSlots[card.thread.colorSlot]).frame(width: 10, height: 10)
                Text(card.thread.title).font(Typo.ui(16, .extrabold)).lineLimit(1)
                Spacer(minLength: 0)
                if card.quietDays >= 14 {
                    Text("Quiet \(card.quietDays)d")
                        .font(Typo.ui(10.5, .bold))
                        .foregroundStyle(Palette.danger.foreground)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.danger.background, in: .capsule)
                }
            }
            if let nextMeeting = card.nextMeeting {
                Label(
                    "Next: \(nextMeeting.title.isEmpty ? "Untitled meeting" : nextMeeting.title) · "
                        + nextMeeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                    systemImage: "calendar")
                    .font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            } else {
                Label("No upcoming meeting", systemImage: "calendar").font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Palette.textQuaternary)
            }
            HStack(spacing: 16) {
                Label("\(card.openActionCount) open", systemImage: "checkmark.circle")
                Label("\(card.peopleCount) people", systemImage: "person.2")
            }
            .font(Typo.ui(12, .semibold)).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NSPSpacing.medium)
        .nspCard()
    }
}
