import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Audio tab, scoped to what a `Segment`/`TimelineEvent` pair
/// actually supports today: a real per-segment player and marker seek.
/// Chapters, a silence map, redaction, and export aren't wired to anything
/// yet — this tab is honest about that rather than showing dead controls.
@MainActor
struct AudioTab: View {
    let meeting: Meeting
    let environment: AppEnvironment

    @State private var segments: [Segment] = []
    @State private var markers: [TimelineEvent] = []
    @State private var loadError: String?
    @State private var playback = AudioPlaybackController()

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            } else if segments.isEmpty {
                ContentUnavailableView(
                    "No audio yet", systemImage: "waveform",
                    description: Text("Segments recorded for this meeting will appear here."))
            } else {
                segmentsSection
                if !markerEvents.isEmpty {
                    markersSection
                }
            }
        }
        .task { await load() }
        .onDisappear { playback.stop() }
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
        guard
            let segment = segments.first(where: {
                marker.sampleOffset >= $0.startSample && marker.sampleOffset < $0.startSample + $0.sampleCount
            })
        else { return }
        let offsetSamples = marker.sampleOffset - segment.startSample
        let offsetSeconds = TimeInterval(offsetSamples) / TimeInterval(segment.sampleRate)
        playback.play(segment: segment, fromOffsetSeconds: offsetSeconds)
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

private struct SegmentRowView: View {
    let segment: Segment
    let playback: AudioPlaybackController

    private var isCurrentlyPlaying: Bool {
        playback.playingSegmentID == segment.segmentID && playback.isPlaying
    }

    private var durationLabel: String {
        let totalSeconds = Int(Double(segment.sampleCount) / Double(segment.sampleRate))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            Button {
                playback.togglePlayPause(segment: segment)
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
