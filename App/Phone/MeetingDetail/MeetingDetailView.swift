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

    @State private var meeting: Meeting?
    @State private var selectedTab: Tab = .overview
    @State private var loadError: String?
    /// Shared across the Audio/Transcript/Insights tabs so switching tabs
    /// mid-playback doesn't stop it, and every tab seeks the same absolute
    /// meeting timeline (`AudioPlaybackController`'s own doc comment).
    @State private var playback = AudioPlaybackController()
    @State private var compositeAudioURL: URL?
    @State private var compositeAudioError: String?

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
            .background(NSPColor.background)
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let meetingLoad: Void = loadMeeting()
            async let compositeLoad: Void = loadCompositeAudio()
            _ = await (meetingLoad, compositeLoad)
        }
        .onDisappear { playback.stop() }
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
                            .foregroundStyle(isSelected ? .white : NSPColor.primaryText)
                            .padding(.horizontal, NSPSpacing.medium)
                            .padding(.vertical, NSPSpacing.small)
                            .background(isSelected ? NSPColor.accent : NSPColor.secondaryBackground, in: .capsule)
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
                NotesTab(meeting: meeting, environment: environment)
            case .transcript:
                TranscriptTab(
                    meeting: meeting, environment: environment, playback: playback, compositeAudioURL: compositeAudioURL
                )
            case .audio:
                AudioTab(
                    meeting: meeting, environment: environment, playback: playback,
                    compositeAudioURL: compositeAudioURL,
                    compositeAudioError: compositeAudioError)
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
            let segments = try await environment.segmentRepository.fetchAll(meetingID: meetingID)
            guard !segments.isEmpty else { return }
            let container = try environment.makeMeetingContainer(meetingID: meetingID)
            compositeAudioURL = try await SegmentStitcher().buildOrReuseComposite(
                segments: segments, container: container)
        } catch {
            compositeAudioError = "\(error)"
        }
    }
}

/// docs/07 §4's Overview tab: duration, availability, processing mode, and
/// lifecycle state, plus the real executive-summary `Insight` once
/// processing has produced one. Chapters and participants still aren't
/// generated by anything this pass — shown as explicit absence, not blank
/// space that looks broken.
private struct OverviewTab: View {
    let meeting: Meeting
    let environment: AppEnvironment

    @State private var executiveSummary: Insight?

    private var durationLabel: String {
        guard meeting.canonicalDuration.sampleCount > 0 else { return "—" }
        let totalSeconds = Int(meeting.canonicalDuration.seconds)
        return String(format: "%d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    private var availabilityLabel: String {
        switch meeting.availability {
        case .complete: return "Complete"
        case .partial(let missing): return "Partial — \(missing.count) segment\(missing.count == 1 ? "" : "s") missing"
        case .recoverable: return "Recoverable"
        case .failed: return "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                MeetingStateBadge(state: meeting.lifecycleState)
                LabeledContent("Duration", value: durationLabel)
                LabeledContent("Availability", value: availabilityLabel)
                LabeledContent("Processing mode", value: meeting.processingMode.rawValue)
                LabeledContent("Started", value: meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .nspCard()

            if let executiveSummary {
                VStack(alignment: .leading, spacing: NSPSpacing.small) {
                    Text("Summary").font(.headline)
                    Text(executiveSummary.text).font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .nspCard()
            } else {
                EmptyTabPlaceholder(
                    title: "No recap yet", systemImage: "sparkles",
                    message: "A flash recap and executive summary appear here once this meeting is processed.")
            }
        }
        .task { await loadExecutiveSummary() }
    }

    private func loadExecutiveSummary() async {
        let insights = try? await environment.insightRepository.fetchAll(meetingID: meeting.meetingID)
        executiveSummary = insights?.first { $0.layer == .executiveSummary }
    }
}

/// A correct, explicit "nothing here yet" state (docs/07 §11) — never a
/// blank view that could be mistaken for a loading or broken screen.
private struct EmptyTabPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
