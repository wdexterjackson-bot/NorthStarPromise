import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Audio tab: a continuous player over the meeting's stitched
/// composite (`SegmentStitcher`) plus marker seek, with the per-segment list
/// kept below for transfer-state visibility (queued/verified/reclaimed) and
/// as a working fallback if the composite couldn't be built. Chapters, a
/// silence map, redaction, and export aren't wired to anything yet — this
/// tab is honest about that rather than showing dead controls.
@MainActor
struct AudioTab: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let playback: AudioPlaybackController
    let compositeAudioURL: URL?
    let compositeAudioError: String?

    @State private var segments: [Segment] = []
    @State private var markers: [TimelineEvent] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            } else if segments.isEmpty {
                ContentUnavailableView(
                    "No audio yet", systemImage: "waveform",
                    description: Text("Segments recorded for this meeting will appear here."))
            } else {
                playerSection
                if !markerEvents.isEmpty {
                    markersSection
                }
                segmentsSection
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var playerSection: some View {
        if let compositeAudioURL {
            AudioPlayerCard(playback: playback, fileURL: compositeAudioURL)
        } else if let compositeAudioError {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                NSPStatusBadge(
                    symbolName: "exclamationmark.triangle.fill", label: "Couldn't prepare audio",
                    tint: NSPColor.statusDanger)
                Text(compositeAudioError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        } else {
            HStack(spacing: NSPSpacing.medium) {
                ProgressView()
                Text("Preparing audio…").font(.callout).foregroundStyle(NSPColor.secondaryText)
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

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Segments").font(.headline)
            ForEach(segments) { segment in
                SegmentRowView(segment: segment, playback: playback)
            }
        }
    }

    private var markersSection: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Markers").font(.headline)
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
            async let fetchedSegments = environment.segmentRepository.fetchAll(meetingID: meeting.meetingID)
            async let fetchedMarkers = environment.timelineEventRepository.fetchAll(meetingID: meeting.meetingID)
            segments = try await fetchedSegments.sorted { $0.sequence < $1.sequence }
            markers = try await fetchedMarkers
        } catch {
            loadError = "\(error)"
        }
    }
}

/// The continuous scrubber player — play/pause, elapsed/remaining time, and
/// a draggable progress bar over the meeting's stitched composite file.
private struct AudioPlayerCard: View {
    let playback: AudioPlaybackController
    let fileURL: URL

    private var progress: Double {
        guard playback.durationSeconds > 0 else { return 0 }
        return playback.currentTimeSeconds / playback.durationSeconds
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(spacing: NSPSpacing.medium) {
            HStack(spacing: NSPSpacing.medium) {
                Button {
                    if playback.playingURL == fileURL {
                        playback.togglePlayPause()
                    } else {
                        playback.play(fileURL: fileURL)
                    }
                } label: {
                    ZStack {
                        Circle().fill(NSPColor.accent.gradient).frame(width: 52, height: 52)
                        Image(
                            systemName: playback.isPlaying && playback.playingURL == fileURL
                                ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                VStack(spacing: NSPSpacing.extraSmall) {
                    ProgressView(value: progress)
                        .tint(NSPColor.accent)
                    HStack {
                        Text(timeLabel(playback.playingURL == fileURL ? playback.currentTimeSeconds : 0))
                        Spacer()
                        Text(timeLabel(playback.durationSeconds))
                    }
                    .font(.caption2)
                    .foregroundStyle(NSPColor.secondaryText)
                }
            }
        }
        .nspCard()
        .task(id: fileURL) {
            // Populates duration/scrubber as soon as the tab appears,
            // without starting playback.
            playback.load(fileURL: fileURL)
        }
    }
}

private struct SegmentRowView: View {
    let segment: Segment
    let playback: AudioPlaybackController

    private var isCurrentlyPlaying: Bool {
        playback.playingURL == segment.localURL && playback.isPlaying
    }

    private var durationLabel: String {
        let totalSeconds = Int(Double(segment.sampleCount) / Double(segment.sampleRate))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            Button {
                guard let localURL = segment.localURL else { return }
                if playback.playingURL == localURL {
                    playback.togglePlayPause()
                } else {
                    playback.play(fileURL: localURL)
                }
            } label: {
                ZStack {
                    Circle().fill(NSPColor.accent.gradient).frame(width: 40, height: 40)
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(segment.localURL == nil)
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text("Segment \(segment.sequence + 1)").font(.body.weight(.medium))
                Text(durationLabel).font(.caption).foregroundStyle(NSPColor.secondaryText)
            }

            Spacer(minLength: 0)

            let appearance = Self.appearance(for: segment.transferState)
            NSPStatusBadge(symbolName: appearance.symbol, label: appearance.label, tint: appearance.tint)
        }
        .nspCard()
    }

    private struct Appearance {
        let symbol: String
        let label: String
        let tint: Color
    }

    private static func appearance(for state: TransferState) -> Appearance {
        switch state {
        case .local: return Appearance(symbol: "iphone", label: "On this device", tint: NSPColor.statusNeutral)
        case .queued: return Appearance(symbol: "clock", label: "Queued", tint: NSPColor.statusInProgress)
        case .inFlight:
            return Appearance(symbol: "arrow.up.circle", label: "Transferring", tint: NSPColor.statusInProgress)
        case .receivedUnverified:
            return Appearance(symbol: "checkmark.circle", label: "Received", tint: NSPColor.statusInProgress)
        case .verified:
            return Appearance(symbol: "checkmark.seal.fill", label: "Verified", tint: NSPColor.statusSuccess)
        case .reclaimed:
            return Appearance(symbol: "icloud.fill", label: "In cloud only", tint: NSPColor.statusNeutral)
        case .failed:
            return Appearance(symbol: "exclamationmark.triangle.fill", label: "Failed", tint: NSPColor.statusDanger)
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
                NSPIconBadge(symbolName: symbolName, tint: NSPColor.statusWarning, size: 26)
                Text(label)
                Spacer()
                Text(timeLabel).foregroundStyle(NSPColor.secondaryText)
            }
            .nspCard()
        }
        .buttonStyle(.plain)
    }
}
