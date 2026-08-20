import NSPCore
import SwiftUI

/// iPad's information architecture (docs/07 §1.1's "expansion rule" and
/// §5): the same five areas the iPhone tab bar exposes, now a sidebar; a
/// content column showing whichever area is selected; and a detail column
/// for the selected meeting — the ruled-paper canvas (`PadRecordingCanvas`)
/// while it's the meeting currently recording, the same `MeetingDetailView`
/// tabs iPhone uses once it isn't.
@MainActor
struct PadRootView: View {
    let environment: AppEnvironment
    @State private var recordingSession: RecordingSession
    // `List(selection:)` requires an optional binding (single-select) —
    // `content` below falls back to `.today` whenever this is `nil`
    // (e.g. the user deselects every sidebar row).
    @State private var selectedArea: AppTab? = .today
    @State private var selectedMeetingID: MeetingID?

    init(environment: AppEnvironment) {
        self.environment = environment
        self._recordingSession = State(initialValue: RecordingSession(environment: environment))
    }

    /// Whether `selectedMeetingID` is the meeting `recordingSession` is
    /// actively capturing right now — the one case the detail column shows
    /// the ruled-paper canvas instead of the regular tabbed detail.
    private var isRecordingSelectedMeeting: Bool {
        guard let selectedMeetingID, selectedMeetingID == recordingSession.meetingID else { return false }
        return recordingSession.state == .recording || recordingSession.state == .paused
            || recordingSession.state == .arming
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
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
    }

    private var sidebar: some View {
        List(selection: $selectedArea) {
            ForEach(AppTab.allCases, id: \.self) { area in
                Label(area.title, systemImage: area.symbolName).tag(area)
            }
        }
        .navigationTitle("North-Star Promise")
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
