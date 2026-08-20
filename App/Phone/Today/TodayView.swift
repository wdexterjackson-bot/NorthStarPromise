import NSPCore
import NSPDesignSystem
import SwiftUI

/// The app's dashboard — the primary launch screen. Beyond docs/07 §4's
/// fixed section order (Now, Needs review, Upcoming, Attention), this adds
/// two cross-meeting views a busy user managing several meetings needs at
/// a glance: every open action item regardless of which meeting produced
/// it, and a Library preview — the "executive assistant" framing behind
/// this screen's design. Sections with nothing to show are simply absent,
/// never invented content (docs/07 §11).
@MainActor
struct TodayView: View {
    let environment: AppEnvironment
    let session: RecordingSession
    let selectTab: (AppTab) -> Void

    @State private var meetings: [Meeting] = []
    @State private var actions: [Action] = []
    @State private var loadError: String?

    private static let openStatuses: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]
    private static let maxActionRows = 5
    private static let maxLibraryRows = 3

    private var meetingTitles: [MeetingID: String] {
        Dictionary(
            uniqueKeysWithValues: meetings.map {
                ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
            })
    }

    private var needsReview: [Meeting] {
        meetings.filter { $0.lifecycleState == .readyForReview || $0.lifecycleState == .partialFailure }
    }

    private var openActions: [Action] {
        actions.filter { Self.openStatuses.contains($0.status) }
            .sorted { lhs, rhs in
                switch (Self.dueDate(lhs), Self.dueDate(rhs)) {
                case (let left?, let right?): return left < right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return false
                }
            }
    }

    private var overdueActionCount: Int {
        let now = environment.clock.now()
        return openActions.filter { action in
            guard let due = Self.dueDate(action) else { return false }
            return due < now
        }.count
    }

    private var meetingsThisWeek: Int {
        let now = environment.clock.now()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        return meetings.filter { $0.startedAt >= weekAgo && $0.startedAt <= now }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                    if let loadError {
                        Text(loadError).font(.caption).foregroundStyle(NSPColor.statusDanger)
                    }
                    statsStrip
                    nowSection
                    needsReviewSection
                    openActionsSection
                    libraryPreviewSection
                }
                .padding(NSPSpacing.large)
            }
            .background(NSPColor.background)
            .navigationTitle("Today")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var statsStrip: some View {
        HStack(spacing: NSPSpacing.medium) {
            DashboardStatChip(value: "\(meetingsThisWeek)", label: "This week", tint: NSPColor.accent)
            DashboardStatChip(value: "\(openActions.count)", label: "Open actions", tint: NSPColor.statusInProgress)
            if overdueActionCount > 0 {
                DashboardStatChip(value: "\(overdueActionCount)", label: "Overdue", tint: NSPColor.statusDanger)
            }
        }
    }

    @ViewBuilder
    private var nowSection: some View {
        switch session.state {
        case .idle:
            startRecordingCard
        case .arming:
            centeredStatusCard(message: "Preparing…")
        case .recording, .paused:
            ActiveSessionCard(session: session)
        case .finalizing:
            centeredStatusCard(message: "Finishing up…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                NSPStatusBadge(
                    symbolName: "exclamationmark.triangle.fill", label: "Couldn't record", tint: NSPColor.statusDanger)
                Text(message).font(.callout).foregroundStyle(NSPColor.secondaryText)
                Button("Try again") { session.dismissFailure() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        }
    }

    private var startRecordingCard: some View {
        Button {
            Task { await session.start() }
        } label: {
            VStack(spacing: NSPSpacing.medium) {
                ZStack {
                    Circle().fill(Color.red.gradient).frame(width: 88, height: 88)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 2) {
                    Text("Start Recording").font(.title3.weight(.semibold))
                    Text("Capture audio on this iPhone")
                        .font(.caption)
                        .foregroundStyle(NSPColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NSPSpacing.extraLarge)
        }
        .buttonStyle(.plain)
        .nspCard()
    }

    private func centeredStatusCard(message: String) -> some View {
        HStack(spacing: NSPSpacing.medium) {
            ProgressView()
            Text(message).font(.callout).foregroundStyle(NSPColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NSPSpacing.large)
        .nspCard()
    }

    @ViewBuilder
    private var needsReviewSection: some View {
        if !needsReview.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Needs Review").font(.title3.weight(.bold))
                ForEach(needsReview) { meeting in
                    NavigationLink(value: meeting.meetingID) {
                        MeetingRow(meeting: meeting).nspCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Every open action across every meeting — "the master list to help
    /// the user stay organized," per the product direction behind this
    /// screen. Each row still names its source meeting and links to it.
    @ViewBuilder
    private var openActionsSection: some View {
        if !openActions.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                sectionHeader("Action Items", seeAllTab: .actions)
                ForEach(openActions.prefix(Self.maxActionRows)) { action in
                    NavigationLink(value: action.meetingID) {
                        DashboardActionRow(
                            action: action, meetingTitle: meetingTitles[action.meetingID] ?? "Untitled meeting",
                            isOverdue: Self.isOverdue(action, now: environment.clock.now()))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A Library preview — recent meetings not already surfaced above, so
    /// the dashboard doubles as "what have I been recording lately"
    /// without requiring a tab switch for the common case.
    @ViewBuilder
    private var libraryPreviewSection: some View {
        let needsReviewIDs = Set(needsReview.map(\.meetingID))
        let recent = meetings.filter { !needsReviewIDs.contains($0.meetingID) }.sorted { $0.startedAt > $1.startedAt }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                sectionHeader("Library", seeAllTab: .library)
                ForEach(recent.prefix(Self.maxLibraryRows)) { meeting in
                    NavigationLink(value: meeting.meetingID) {
                        MeetingRow(meeting: meeting).nspCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, seeAllTab: AppTab) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            Button("See All") { selectTab(seeAllTab) }
                .font(.subheadline)
        }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            async let fetchedMeetings = environment.meetingRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            async let fetchedActions = environment.actionRepository.fetchAll(workspaceID: workspaceID)
            meetings = try await fetchedMeetings
            actions = try await fetchedActions
        } catch {
            loadError = "\(error)"
        }
    }

    private static func dueDate(_ action: Action) -> Date? {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date
        case .unresolved: return nil
        }
    }

    private static func isOverdue(_ action: Action, now: Date) -> Bool {
        guard let due = dueDate(action) else { return false }
        return due < now
    }
}

/// A compact glanceable stat — "N meetings this week," "N open actions."
private struct DashboardStatChip: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(NSPColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NSPSpacing.medium)
        .background(NSPColor.cardBackground, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// A cross-meeting action row for the dashboard — lighter than
/// `ActionRowCard` (no status-transition menu here; full management stays
/// in the Actions tab) since this view exists to answer "what's open and
/// where did it come from," not to manage every action inline.
private struct DashboardActionRow: View {
    let action: Action
    let meetingTitle: String
    let isOverdue: Bool

    private var dueLabel: String? {
        switch action.date {
        case .explicit(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .inferred(let date): return "\(date.formatted(date: .abbreviated, time: .omitted)) (inferred)"
        case .unresolved: return nil
        }
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            NSPIconBadge(
                symbolName: action.status.symbolName, tint: isOverdue ? NSPColor.statusDanger : action.status.tint)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(action.text).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: NSPSpacing.extraSmall) {
                    Text(meetingTitle)
                    if let dueLabel {
                        Text("·")
                        Text(dueLabel)
                    }
                }
                .font(.caption)
                .foregroundStyle(isOverdue ? NSPColor.statusDanger : NSPColor.secondaryText)
            }

            Spacer(minLength: 0)

            if isOverdue {
                Text("Overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, NSPSpacing.small)
                    .padding(.vertical, 4)
                    .background(NSPColor.statusDanger, in: .capsule)
            }
        }
        .nspCard()
    }
}
