import NSPCore
import NSPDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// docs/07 §4's Audio tab: a single continuous player over the meeting's
/// stitched composite (`SegmentStitcher`) plus marker seek — deliberately
/// never a per-segment list. Segments are this app's internal durability
/// unit (Invariant I3), not something the user should have to think about;
/// every meeting reads as exactly one recording here, regardless of how
/// many segments it was actually captured across. Chapters, a silence map,
/// redaction, and export aren't wired to anything yet — this tab is honest
/// about that rather than showing dead controls.
@MainActor
struct AudioTab: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let playback: AudioPlaybackController
    let compositeAudioURL: URL?
    let compositeAudioError: String?
    /// Called once an import into this meeting finishes durably saving —
    /// the caller's cue to reload `meeting` itself (title/lifecycle state
    /// changed), not just this tab's own `segments`.
    var onMeetingChanged: () -> Void = {}

    @State private var segments: [Segment] = []
    @State private var markers: [TimelineEvent] = []
    @State private var loadError: String?
    @State private var isShowingImportPicker = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            if let loadError {
                Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            } else if segments.isEmpty {
                emptyState
            } else {
                playerSection
                if !markerEvents.isEmpty {
                    markersSection
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $isShowingImportPicker) {
            AudioDocumentPicker(
                startingDirectory: environment.defaultImportExportDirectoryURL,
                onPick: { url in Task { await performImport(from: url) } })
        }
        .alert(
            "Couldn't import audio",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: NSPSpacing.medium) {
            ContentUnavailableView(
                "No audio yet", systemImage: "waveform",
                description: Text("The recording for this meeting will appear here."))
            if isImporting {
                ProgressView("Importing audio…")
            } else {
                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Import Recording", systemImage: "square.and.arrow.down")
                        .font(Typo.ui(13, .semibold))
                        .padding(.horizontal, NSPSpacing.large)
                        .padding(.vertical, NSPSpacing.medium)
                        .background(Palette.accent.foreground, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func performImport(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let coordinator = AudioImportCoordinator(environment: environment)
            _ = try await coordinator.importAudio(from: url, intoExisting: meeting.meetingID)
            onMeetingChanged()
            // Everything analyzes automatically once the audio lands — no
            // title prompt needed here, unlike a fresh import, since this
            // meeting was already named when it was added to the agenda.
            if let selfPersonID = environment.selfPersonID {
                let intelligence = environment.intelligenceCoordinator
                Task {
                    await intelligence.processMeeting(
                        meeting.meetingID, selfPersonID: selfPersonID, options: PostRecordingProcessingOptions())
                }
            }
            await load()
        } catch {
            importError = "\(error)"
        }
    }

    @ViewBuilder
    private var playerSection: some View {
        if let compositeAudioURL {
            AudioPlayerCard(
                playback: playback, environment: environment, meeting: meeting, compositeAudioURL: compositeAudioURL)
        } else if let compositeAudioError {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                NSPStatusBadge(
                    symbolName: "exclamationmark.triangle.fill", label: "Couldn't prepare audio",
                    tint: Palette.danger.foreground)
                Text(compositeAudioError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        } else {
            HStack(spacing: NSPSpacing.medium) {
                ProgressView()
                Text("Preparing audio…").font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NSPSpacing.large)
            .nspCard()
        }
    }

    private var markerEvents: [TimelineEvent] {
        markers.filter {
            if case .marker = $0.type { return true }
            return false
        }
    }

    private var markersSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Markers").font(Typo.ui(15, .bold))
            ForEach(markerEvents) { marker in
                MarkerRowView(marker: marker, sampleRate: meeting.canonicalDuration.sampleRate) {
                    seek(to: marker)
                }
            }
        }
    }

    private func seek(to marker: TimelineEvent) {
        guard let compositeAudioURL else { return }
        let offsetSeconds = TimeInterval(marker.sampleOffset) / TimeInterval(meeting.canonicalDuration.sampleRate)
        playback.play(fileURL: compositeAudioURL, fromOffsetSeconds: offsetSeconds)
    }

    private func load() async {
        do {
            async let fetchedSegments = environment.segmentRepository.fetchAll(owner: .meeting(meeting.meetingID))
            async let fetchedMarkers = environment.timelineEventRepository.fetchAll(owner: .meeting(meeting.meetingID))
            segments = try await fetchedSegments.sorted { $0.sequence < $1.sequence }
            markers = try await fetchedMarkers
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct MarkerRowView: View {
    let marker: TimelineEvent
    let sampleRate: Int
    let onSeek: () -> Void

    private var kind: MarkerKind? {
        if case .marker(let kind) = marker.type { return kind }
        return nil
    }

    private var timeLabel: String {
        let totalSeconds = Int(Double(marker.sampleOffset) / Double(max(sampleRate, 1)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var label: String {
        switch kind {
        case .important: return "Important"
        case .actionItem: return "Action item"
        case .question: return "Question"
        case nil: return "Marker"
        }
    }

    private var symbolName: String {
        switch kind {
        case .important: return "star.fill"
        case .actionItem: return "checkmark.circle"
        case .question: return "questionmark.circle"
        case nil: return "bookmark.fill"
        }
    }

    var body: some View {
        Button(action: onSeek) {
            HStack(spacing: NSPSpacing.medium) {
                NSPIconBadge(symbolName: symbolName, tint: Palette.warn.foreground, size: 26)
                Text(label)
                Spacer()
                Text(timeLabel).foregroundStyle(Palette.textTertiary)
            }
            .nspCard()
        }
        .buttonStyle(.plain)
    }
}
