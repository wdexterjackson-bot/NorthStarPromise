import NSPCore
import NSPDesignSystem
import SwiftUI
import UIKit

/// "What do I need to do today" — narrower than it used to be. `DashboardView`
/// is now the primary launch screen and owns the "manage everything, across
/// all time" concerns (a full library preview, every open action
/// regardless of due date); Today keeps only what's actually about today:
/// the active/next recording, meetings that just finished processing and
/// need review, today's Scheduled Recordings, and actions due today.
/// Sections with nothing to show are simply absent, never invented content
/// (docs/07 §11).
@MainActor
struct TodayView: View {
    let environment: AppEnvironment
    let session: RecordingSession
    let selectTab: (AppTab) -> Void
    /// When set (iPad), tapping a meeting calls this instead of pushing
    /// via `NavigationLink` — iPad routes selection into a third column
    /// rather than a navigation stack (`PadRootView`). `nil` (default)
    /// preserves the iPhone push behavior unchanged.
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var meetings: [Meeting] = []
    @State private var actions: [Action] = []
    @State private var scheduledRecordings: [ScheduledRecording] = []
    @State private var isShowingScheduleForm = false
    @State private var editingScheduledRecording: ScheduledRecording?
    @State private var loadError: String?

    private static let openStatuses: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]
    private static let maxActionRows = 5

    private var meetingTitles: [MeetingID: String] {
        Dictionary(
            uniqueKeysWithValues: meetings.map {
                ($0.meetingID, $0.isTitleSensitive || $0.title.isEmpty ? "Untitled meeting" : $0.title)
            })
    }

    private var needsReview: [Meeting] {
        meetings.filter { $0.lifecycleState == .readyForReview || $0.lifecycleState == .partialFailure }
    }

    /// Unlike `DashboardView`'s copy of this same shape, filtered to only
    /// what's actually due today — Today answers "what do I need to do
    /// today," not "show me every open action ever."
    private var actionsDueToday: [Action] {
        actions.filter { action in
            Self.openStatuses.contains(action.status)
                && Self.dueDate(action).map(Calendar.current.isDateInToday)
                    ?? false
        }
        .sorted { lhs, rhs in (Self.dueDate(lhs) ?? .distantFuture) < (Self.dueDate(rhs) ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                    if let loadError {
                        Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                    }
                    dateHeader
                    nowSection
                    needsReviewSection
                    upcomingSection
                    dueTodayActionsSection
                }
                .padding(NSPSpacing.large)
            }
            .background(Palette.canvas)
            .navigationTitle("Today")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: environment.contentRevision) { _, _ in Task { await load() } }
        }
        .sheet(isPresented: $isShowingScheduleForm) {
            ScheduleRecordingFormView(environment: environment, onDone: { Task { await load() } })
        }
        .sheet(item: $editingScheduledRecording) { item in
            ScheduleRecordingFormView(environment: environment, existingItem: item, onDone: { Task { await load() } })
        }
    }

    /// Today only, unlike `DashboardView`'s unfiltered copy of this same
    /// section — Today answers "what's happening today," not "everything
    /// scheduled, ever."
    private var todaysScheduledRecordings: [ScheduledRecording] {
        scheduledRecordings.filter { Calendar.current.isDateInToday($0.scheduledStart) }
    }

    /// Behind `FeatureFlag.scheduledRecording` (default off) — docs/07 §4's
    /// planned Today section, formalized from covering calendar-derived
    /// entries only to covering schedule-created ones too. Pulled into its
    /// own view (`TodayDashboardSupport.swift`) purely to stay under this
    /// repo's 250-line type-body budget, same as `TodayPromptSheets`.
    @ViewBuilder
    private var upcomingSection: some View {
        if environment.featureFlagProvider.isEnabled(.scheduledRecording) {
            UpcomingRecordingsSection(
                items: todaysScheduledRecordings, onScheduleTapped: { isShowingScheduleForm = true },
                onEdit: { editingScheduledRecording = $0 }, onCancel: { item in Task { await cancelSchedule(item) } })
        }
    }

    /// The full date ("Friday, August 21, 2026") — `.navigationTitle("Today")`
    /// already names the screen, this just grounds it in an actual date.
    private var dateHeader: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
            .font(Typo.ui(13, .medium))
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nowSection: some View {
        switch session.state {
        case .idle:
            VStack(spacing: NSPSpacing.medium) {
                startRecordingCard
                if onSelectMeeting != nil {
                    NewNoteButton(session: session)
                }
            }
        case .draft:
            DraftingNotesCard(session: session, onSelectMeeting: onSelectMeeting)
        case .arming:
            centeredStatusCard(message: "Preparing…")
        case .recording, .paused:
            ActiveSessionCard(session: session)
        case .finalizing:
            centeredStatusCard(message: "Finishing up…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                NSPStatusBadge(
                    symbolName: "exclamationmark.triangle.fill", label: "Couldn't record",
                    tint: Palette.danger.foreground)
                Text(message).font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
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
                    Text("Start Recording").font(Typo.ui(17, .bold))
                    Text("Capture audio on this \(Self.deviceLabel)")
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Palette.textTertiary)
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
            Text(message).font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NSPSpacing.large)
        .nspCard()
    }

    @ViewBuilder
    private var needsReviewSection: some View {
        if !needsReview.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Needs Review").font(Typo.ui(17, .extrabold))
                ForEach(needsReview) { meeting in
                    meetingLink(meeting.meetingID) {
                        MeetingRow(meeting: meeting, onDelete: { Task { await deleteMeeting(meeting.meetingID) } })
                            .nspCard()
                    }
                }
            }
        }
    }

    /// Actions due specifically today — `DashboardView` shows the unfiltered
    /// "every open action" version of this same reusable component; this is
    /// the narrower, today-only view.
    @ViewBuilder
    private var dueTodayActionsSection: some View {
        if !actionsDueToday.isEmpty {
            OpenActionsSection(
                actions: Array(actionsDueToday.prefix(Self.maxActionRows)), meetingTitles: meetingTitles,
                now: environment.clock.now(), onSelectMeeting: onSelectMeeting, onSeeAll: { selectTab(.actions) },
                onDelete: { actionID in Task { await deleteAction(actionID) } })
        }
    }

    /// Routes a meeting tap to either a navigation push (iPhone) or the
    /// `onSelectMeeting` callback (iPad) — see the property's doc comment.
    /// Still used directly by `needsReviewSection` above, which stays small
    /// enough not to need its own extracted view.
    @ViewBuilder
    private func meetingLink<Label: View>(_ meetingID: MeetingID, @ViewBuilder label: () -> Label) -> some View {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(meetingID)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: meetingID) { label() }
                .buttonStyle(.plain)
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
        if environment.featureFlagProvider.isEnabled(.scheduledRecording) {
            scheduledRecordings =
                (try? await environment.scheduledRecordingRepository.fetchPending(
                    workspaceID: workspaceID)) ?? []
        }
    }

    private func deleteMeeting(_ meetingID: MeetingID) async {
        do {
            try await environment.deleteMeeting(meetingID)
            await load()
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteAction(_ actionID: ActionID) async {
        do {
            try await environment.actionRepository.delete(actionID)
            await load()
        } catch {
            loadError = "\(error)"
        }
    }

    private func cancelSchedule(_ item: ScheduledRecording) async {
        do {
            try await environment.scheduledRecordingCoordinator.cancelSchedule(item)
            await load()
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

    static var deviceLabel: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}
