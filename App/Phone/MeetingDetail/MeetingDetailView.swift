import NSPCore
import NSPDesignSystem
import NSPMedia
import SwiftUI

/// docs/07 §4's nine meeting-detail tabs. A horizontal tab strip rather
/// than a native `TabView` — nine destinations don't fit a bottom tab bar
/// legibly. Overview, Notes, Audio, and Actions are functional against
/// real data; every other tab renders the correct "nothing here yet"
/// state (docs/07 §11) rather than fabricated content, since
/// transcription, summarization, attachments, sharing, and the processing
/// log aren't wired to any pipeline in this pass.
@MainActor
struct MeetingDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case notes = "Notes"
        case transcript = "Transcript"
        case audio = "Audio"
        case actions = "Actions"
        case insights = "Insights"
        case attachments = "Attachments"
        case sharing = "Sharing"
        case processingLog = "Processing log"
        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .overview: return "square.text.square"
            case .notes: return "note.text"
            case .transcript: return "text.bubble"
            case .audio: return "waveform"
            case .actions: return "checkmark.circle"
            case .insights: return "lightbulb"
            case .attachments: return "paperclip"
            case .sharing: return "square.and.arrow.up"
            case .processingLog: return "list.bullet.clipboard"
            }
        }
    }

    let meetingID: MeetingID
    let environment: AppEnvironment
    /// Set when arriving from an Ask citation tap (`AskView`'s doc
    /// comment) — jumps straight to the Transcript tab and seeks/scrolls
    /// to this turn once it loads, instead of the usual `.overview` start.
    private let initialSeekTurnID: TranscriptTurnID?

    /// No-op unless this view is actually pushed onto a `NavigationStack`
    /// or presented as a sheet. On iPad's `NavigationSplitView` detail
    /// column (where this view is neither) it has no effect — `PadRootView`
    /// independently clears `selectedMeetingID` for that case instead.
    @Environment(\.dismiss) private var dismiss

    @State private var meeting: Meeting?
    @State private var selectedTab: Tab
    @State private var loadError: String?
    /// Shared across the Audio/Transcript/Insights tabs so switching tabs
    /// mid-playback doesn't stop it, and every tab seeks the same absolute
    /// meeting timeline (`AudioPlaybackController`'s own doc comment).
    @State private var playback = AudioPlaybackController()
    @State private var compositeAudioURL: URL?
    @State private var compositeAudioError: String?

    init(
        meetingID: MeetingID, environment: AppEnvironment, initialTab: Tab = .overview,
        initialSeekTurnID: TranscriptTurnID? = nil
    ) {
        self.meetingID = meetingID
        self.environment = environment
        self.initialSeekTurnID = initialSeekTurnID
        _selectedTab = State(initialValue: initialTab)
    }

    private var titleText: String {
        guard let meeting else { return "" }
        return meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NSPSpacing.large)
            }
            .background(Palette.canvas)
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let meetingLoad: Void = loadMeeting()
            async let compositeLoad: Void = loadCompositeAudio()
            _ = await (meetingLoad, compositeLoad)
        }
        .onDisappear { playback.stop() }
        .onChange(of: environment.lastDeletedMeetingID) { _, deletedID in
            if deletedID == meetingID { dismiss() }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NSPSpacing.small) {
                ForEach(Tab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.symbolName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                            .padding(.horizontal, NSPSpacing.medium)
                            .padding(.vertical, NSPSpacing.small)
                            .background(isSelected ? Palette.accent.foreground : Palette.fill, in: .capsule)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, NSPSpacing.large)
            .padding(.vertical, NSPSpacing.small)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView(
                "Couldn't load meeting", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if let meeting {
            switch selectedTab {
            case .overview:
                OverviewTab(meeting: meeting, environment: environment)
            case .notes:
                NotesTab(
                    meeting: meeting, environment: environment, playback: playback,
                    compositeAudioURL: compositeAudioURL)
            case .transcript:
                TranscriptTab(
                    meeting: meeting, environment: environment, playback: playback,
                    compositeAudioURL: compositeAudioURL, initialSeekTurnID: initialSeekTurnID
                )
            case .audio:
                AudioTab(
                    meeting: meeting, environment: environment, playback: playback,
                    compositeAudioURL: compositeAudioURL, compositeAudioError: compositeAudioError,
                    onMeetingChanged: {
                        Task {
                            await loadMeeting()
                            await loadCompositeAudio()
                        }
                    })
            case .actions:
                ActionsTab(meeting: meeting, environment: environment)
            case .insights:
                InsightsTab(
                    meeting: meeting, environment: environment, playback: playback, compositeAudioURL: compositeAudioURL
                )
            case .attachments:
                EmptyTabPlaceholder(
                    title: "No attachments", systemImage: "paperclip",
                    message: "Photos, scans, and imported files will appear here.")
            case .sharing:
                EmptyTabPlaceholder(
                    title: "Nothing shared yet", systemImage: "square.and.arrow.up",
                    message: "Share this meeting to see share grants here.")
            case .processingLog:
                EmptyTabPlaceholder(
                    title: "No processing yet", systemImage: "list.bullet.clipboard",
                    message: "Job history appears once processing starts.")
            }
        } else {
            ProgressView()
        }
    }

    private func loadMeeting() async {
        do {
            meeting = try await environment.meetingRepository.find(meetingID)
        } catch {
            loadError = "\(error)"
        }
    }

    /// Builds (or reuses the disk-cached) continuous audio file for this
    /// meeting so the Audio/Transcript/Insights tabs can all play/seek one
    /// absolute timeline instead of per-segment files. A meeting with no
    /// segments yet leaves both `compositeAudioURL`/`compositeAudioError`
    /// nil — `AudioTab`'s own segment load already drives the "No audio
    /// yet" empty state for that case.
    private func loadCompositeAudio() async {
        do {
            let segments = try await environment.segmentRepository.fetchAll(owner: .meeting(meetingID))
            guard !segments.isEmpty else { return }
            let container = try environment.makeMeetingContainer(meetingID: meetingID)
            compositeAudioURL = try await SegmentStitcher().buildOrReuseComposite(
                segments: segments, container: container)
        } catch {
            compositeAudioError = "\(error)"
        }
    }
}

/// A correct, explicit "nothing here yet" state (docs/07 §11) — never a
/// blank view that could be mistaken for a loading or broken screen.
struct EmptyTabPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
