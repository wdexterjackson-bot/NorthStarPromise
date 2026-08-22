import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The primary launch screen, rebuilt against `DASHBOARD_SPEC.md` §5: one
/// composed `DashboardModel` (`AppEnvironment.composeDashboard()`) renders
/// the spec's core sections — Next Up, the day threaded, threads in
/// motion, needs you, what your history noticed — while this app's own
/// still-live features (scheduled recordings, Projects, People) stay
/// reachable below them per the Dashboard scope plan's Q2 resolution
/// (8 tabs kept, re-skinned rather than reduced to the mockup's 5). Sections
/// with nothing to show are simply absent, never invented content (docs/07
/// §11).
@MainActor
struct DashboardView: View {
    let environment: AppEnvironment
    let session: RecordingSession
    let selectTab: (AppTab) -> Void
    /// iPad-only, same meaning as every other screen's identical property:
    /// non-nil routes a meeting tap into the third column instead of a
    /// navigation push.
    var onSelectMeeting: ((MeetingID) -> Void)?
    /// iPad-only — switches `PadRootView`'s area directly instead of
    /// pushing. `nil` (iPhone) means `openToday()` pushes `TodayView` onto
    /// this view's own `NavigationStack` instead.
    var onOpenToday: (() -> Void)?

    @State private var model: DashboardModel?
    @State private var needsReviewMeetings: [Meeting] = []
    @State private var projects: [Project] = []
    @State private var scheduledRecordings: [ScheduledRecording] = []
    @State private var loadError: String?
    @State private var isShowingToday = false
    @State private var isShowingScheduleForm = false
    @State private var editingScheduledRecording: ScheduledRecording?
    @State private var scrollOffset: CGFloat = 0
    @State private var isShowingAudioImportPicker = false
    @State private var isShowingAmbientMode = false

    private static let maxLibraryRows = 6
    private var isHeaderCollapsed: Bool { scrollOffset < -90 }

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self, value: proxy.frame(in: .named("dashboardScroll")).minY)
                }
                .frame(height: 0)

                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    if let loadError {
                        Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                    }
                    DashboardHeaderSection(
                        dateText: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        headline: model?.headline ?? "", isCollapsed: isHeaderCollapsed)
                    DashboardRecallField(corpusCount: model?.corpusCount ?? 0, action: { selectTab(.ask) })
                    attentionSection
                    nextUpSection
                    dayThreadedSection
                    threadsInMotionSection
                    needsYouSection
                    signalsSection
                    upcomingSection
                    projectsSection
                    peopleEntryCard
                }
                .padding(.horizontal, Metrics.screenMarginPhone)
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
            .coordinateSpace(name: "dashboardScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if isHeaderCollapsed { ToolbarItem(placement: .principal) { EmptyView() } } }
            .overlay(alignment: .bottomTrailing) {
                DashboardCaptureButton(
                    isRecording: session.state != .idle,
                    onStartMeeting: {
                        Task { await session.start() }
                        openToday()
                    },
                    onStartMentalNote: {
                        Task { await session.startBrainDump() }
                        openToday()
                    },
                    onImportAudio: { isShowingAudioImportPicker = true },
                    onStartAmbientMode: { isShowingAmbientMode = true }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 100)
            }
            .audioImportSheets(
                isShowingPicker: $isShowingAudioImportPicker, environment: environment,
                onDone: { Task { await load() } }
            )
            .sheet(isPresented: $isShowingAmbientMode) {
                AmbientModeView(environment: environment)
            }
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .navigationDestination(for: NSPThreadID.self) { threadID in
                ThreadDetailView(threadID: threadID, environment: environment, onSelectMeeting: onSelectMeeting)
            }
            .navigationDestination(isPresented: $isShowingToday) {
                TodayView(environment: environment, session: session, selectTab: selectTab)
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: environment.contentRevision) { _, _ in Task { await load() } }
            .sheet(isPresented: $isShowingScheduleForm) {
                ScheduleRecordingFormView(environment: environment, onDone: { Task { await load() } })
            }
            .sheet(item: $editingScheduledRecording) { item in
                ScheduleRecordingFormView(
                    environment: environment, existingItem: item, onDone: { Task { await load() } })
            }
        }
    }

    @ViewBuilder
    private var nextUpSection: some View {
        if let brief = model?.nextUp {
            NextUpCard(
                brief: brief, onOpenBrief: { openMeeting(brief.meeting.meetingID) },
                onJoin: { openMeeting(brief.meeting.meetingID) })
        } else if model != nil {
            ContentUnavailableView(
                "That's the day", systemImage: "checkmark.circle",
                description: Text("Nothing else scheduled today."))
        }
    }

    @ViewBuilder
    private var dayThreadedSection: some View {
        if let agenda = model?.agenda, !agenda.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("The day, threaded", trailingAction: ("Agenda", openToday))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(agenda.enumerated()), id: \.element.id) { index, item in
                        Button {
                            openMeeting(item.meetingID)
                        } label: {
                            DashboardAgendaRow(item: item, isLast: index == agenda.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var threadsInMotionSection: some View {
        if let cards = model?.threadsInMotion, !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Threads in motion", trailingAction: ("See all", { selectTab(.threads) }))
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        NavigationLink(value: card.threadID) { ThreadMotionCard(card: card, action: {}) }
                        if index < cards.count - 1 { Divider().overlay(Palette.divider).padding(.leading, 14) }
                    }
                }
                .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var needsYouSection: some View {
        if let needsYou = model?.needsYou, !needsYou.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "Needs you",
                    inlineChip: needsYou.overdueCount > 0 ? ("\(needsYou.overdueCount) overdue", .danger) : nil,
                    trailingAction: ("\(needsYou.openCount) open", { selectTab(.actions) }))
                VStack(spacing: 0) {
                    ForEach(Array(needsYou.items.enumerated()), id: \.element.id) { index, item in
                        NeedsYouRow(item: item, onComplete: { Task { await completeAction(item.actionID) } })
                        if index < needsYou.items.count - 1 {
                            Divider().overlay(Palette.divider).padding(.leading, 14)
                        }
                    }
                }
                .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var signalsSection: some View {
        if let signals = model?.signals, !signals.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeader("What your history noticed")
                ForEach(signals) { DashboardSignalCard(signal: $0) }
            }
        }
    }

    /// Kept from the pre-redesign Dashboard — meetings that finished
    /// processing with something still needing a look. Not part of the
    /// spec's own layout, but real, still-live functionality this app had
    /// before (Q2's "keep existing functionality" resolution).
    @ViewBuilder
    private var attentionSection: some View {
        DashboardAttentionSection(
            meetings: needsReviewMeetings, onSelectMeeting: onSelectMeeting,
            onDelete: { meetingID in Task { await deleteMeeting(meetingID) } })
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if environment.featureFlagProvider.isEnabled(.scheduledRecording) {
            UpcomingRecordingsSection(
                items: scheduledRecordings, onScheduleTapped: { isShowingScheduleForm = true },
                onEdit: { editingScheduledRecording = $0 }, onCancel: { item in Task { await cancelSchedule(item) } })
        }
    }

    private var projectsSection: some View {
        DashboardProjectsSection(
            projects: Array(projects.prefix(Self.maxLibraryRows)), onSeeAll: { selectTab(.projects) })
    }

    private var peopleEntryCard: some View {
        DashboardEntryCard(
            symbolName: "person.2.fill", title: "People", subtitle: "Who you're meeting with",
            action: { selectTab(.people) })
    }

    private func openToday() {
        if let onOpenToday {
            onOpenToday()
        } else {
            isShowingToday = true
        }
    }

    private func openMeeting(_ meetingID: MeetingID) {
        onSelectMeeting?(meetingID)
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            model = try await environment.composeDashboard()
            let allMeetings = try await environment.meetingRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            needsReviewMeetings = allMeetings.filter {
                $0.lifecycleState == .readyForReview || $0.lifecycleState == .partialFailure
            }
            projects = try await environment.projectRepository.fetchAll(workspaceID: workspaceID)
        } catch {
            loadError = "\(error)"
        }
        if environment.featureFlagProvider.isEnabled(.scheduledRecording) {
            scheduledRecordings =
                (try? await environment.scheduledRecordingRepository.fetchPending(workspaceID: workspaceID)) ?? []
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

    private func cancelSchedule(_ item: ScheduledRecording) async {
        do {
            try await environment.scheduledRecordingCoordinator.cancelSchedule(item)
            await load()
        } catch {
            loadError = "\(error)"
        }
    }

    private func completeAction(_ actionID: ActionID) async {
        do {
            guard var action = try await environment.actionRepository.find(actionID) else { return }
            action.status = .done
            try await environment.actionRepository.update(action, at: environment.clock.now())
            await load()
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
