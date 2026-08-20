import NSPCore
import NSPDesignSystem
import SwiftUI

/// iPad's information architecture (docs/07 §1.1's "expansion rule" and
/// §5): the same five areas the iPhone tab bar exposes, switched via a
/// horizontal button bar at the top of the leading column (no separate
/// sidebar list — a persistent left-hand column of five rows was wasted
/// width next to a top bar that does the same job); a detail column for
/// the selected meeting — the ruled-paper canvas (`PadRecordingCanvas`)
/// while it's the meeting currently recording, the same `MeetingDetailView`
/// tabs iPhone uses once it isn't.
@MainActor
struct PadRootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession
    // `content` falls back to `.today` whenever this is `nil`.
    @State private var selectedArea: AppTab? = .today
    @State private var selectedMeetingID: MeetingID?
    /// `.detailOnly` while drafting/recording (`isRecordingSelectedMeeting`)
    /// — the ruled-paper canvas takes the full window width with no area
    /// switcher competing for space; `.all` otherwise. Starting from `.all`
    /// rather than `.automatic` matters: for a plain two-column split,
    /// `.automatic` collapses the leading column away by default on this
    /// size class — exactly the area-switcher-and-content column this pass
    /// is trying to keep permanently visible, not turn into a togglable
    /// sidebar.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
    }

    /// Whether `selectedMeetingID` is the meeting `recordingSession` owns
    /// right now — either actively capturing, or a pre-recording draft
    /// (docs/07 §5) — the cases where the detail column shows the
    /// ruled-paper canvas instead of the regular tabbed detail.
    private var isRecordingSelectedMeeting: Bool {
        guard let selectedMeetingID, selectedMeetingID == recordingSession.meetingID else { return false }
        return recordingSession.state == .recording || recordingSession.state == .paused
            || recordingSession.state == .arming || recordingSession.state == .draft
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            leadingColumn
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        // A new recording jumps the detail column to its canvas
        // automatically — the whole point of starting on iPad is to write
        // while it records, not to hunt for the meeting afterward.
        .onChange(of: recordingSession.meetingID) { _, newValue in
            if let newValue { selectedMeetingID = newValue }
        }
        .onChange(of: isRecordingSelectedMeeting) { _, isRecording in
            columnVisibility = isRecording ? .detailOnly : .all
        }
    }

    private var leadingColumn: some View {
        VStack(spacing: 0) {
            areaSwitcher
            Divider()
            content
        }
        .navigationTitle("North-Star Promise")
    }

    /// A segmented control across the top — replaces what used to be a
    /// persistent left-hand sidebar list (docs/07 §1.1's five areas). A
    /// segmented control (rather than the capsule-button row
    /// `MeetingDetailView`'s tab strip uses) is what actually fits five
    /// labelled options in this column's width without scrolling or
    /// clipping — that wider capsule style was designed for a roomy detail
    /// column, not this narrower one.
    private var areaSwitcher: some View {
        Picker(
            "Area",
            selection: Binding(get: { selectedArea ?? .today }, set: { selectedArea = $0 })
        ) {
            ForEach(AppTab.allCases, id: \.self) { area in
                Text(area.title).tag(area)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, NSPSpacing.large)
        .padding(.vertical, NSPSpacing.small)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedArea ?? .today {
        case .today:
            TodayView(
                environment: environment, session: recordingSession, selectTab: { selectedArea = $0 },
                onSelectMeeting: { selectedMeetingID = $0 })
        case .library:
            LibraryView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .ask:
            AskView(environment: environment)
        case .actions:
            ActionsView(environment: environment, onSelectMeeting: { selectedMeetingID = $0 })
        case .settings:
            SettingsView(environment: environment)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedMeetingID {
            if isRecordingSelectedMeeting {
                PadRecordingCanvas(environment: environment, session: recordingSession)
            } else {
                MeetingDetailView(meetingID: selectedMeetingID, environment: environment)
            }
        } else {
            ContentUnavailableView(
                "Select a meeting", systemImage: "person.2",
                description: Text("Choose a meeting from Today or Library to see it here."))
        }
    }
}
