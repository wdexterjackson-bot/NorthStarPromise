import NSPCore
import NSPDesignSystem
import NSPMedia
import NSPPersistence
import SwiftUI
import UIKit

/// The Audio tab's transport: play/pause, ±15s skip, playback speed, a
/// real waveform with a draggable trim range, Share, and Studio Voice —
/// Apple's own Voice Memos feature set, built against real signal
/// processing (`WaveformPeakExtractor`, `AudioClipExporter`,
/// `StudioVoiceEnhancer`), not placeholder controls. Trim and Studio Voice
/// never touch the canonical segments or the stitched composite (Invariant
/// I3) — both only ever produce new files in `MeetingContainer`'s
/// `derived/` directory.
struct AudioPlayerCard: View {
    let playback: AudioPlaybackController
    let environment: AppEnvironment
    let meeting: Meeting
    let compositeAudioURL: URL

    @State private var container: MeetingContainer?
    @State private var editState = AudioEditState.empty
    @State private var peaks: [Float] = []
    @State private var isTrimming = false
    @State private var trimStartSeconds: TimeInterval = 0
    @State private var trimEndSeconds: TimeInterval = 0
    @State private var isEnhancing = false
    @State private var enhanceError: String?
    @State private var isExportingClip = false
    @State private var exportError: String?
    @State private var shareURL: URL?

    /// Studio Voice on and already enhanced → the enhanced derived file;
    /// otherwise the plain stitched composite. Neither is ever the
    /// canonical segments themselves.
    private var effectiveFileURL: URL {
        guard editState.studioVoiceEnabled, let container else { return compositeAudioURL }
        let enhancedURL = container.derivedDirectoryURL.appendingPathComponent("studio.m4a")
        return FileManager.default.fileExists(atPath: enhancedURL.path) ? enhancedURL : compositeAudioURL
    }

    private var progress: Double {
        guard playback.durationSeconds > 0 else { return 0 }
        return playback.currentTimeSeconds / playback.durationSeconds
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            transportRow
            if playback.durationSeconds > 0 { scrubberOrWaveform }
            AudioEditControlsRow(
                isTrimming: isTrimming, hasTrim: editState.hasTrim, trimStartSeconds: trimStartSeconds,
                trimEndSeconds: trimEndSeconds, savedTrimStartSeconds: trimStartSecondsFromState,
                savedTrimEndSeconds: trimEndSecondsFromState, studioVoiceEnabled: editState.studioVoiceEnabled,
                isEnhancing: isEnhancing, timeLabel: timeLabel, onCancelTrim: { isTrimming = false },
                onSaveTrim: saveTrim, onClearTrim: clearTrim, onSetStudioVoice: setStudioVoice)
            if let enhanceError {
                Text(enhanceError).font(Typo.ui(10.5, .medium)).foregroundStyle(Palette.danger.foreground)
            }
            if let exportError {
                Text(exportError).font(Typo.ui(10.5, .medium)).foregroundStyle(Palette.danger.foreground)
            }
        }
        .nspCard()
        .task(id: compositeAudioURL) { await initialLoad() }
        .onChange(of: editState.studioVoiceEnabled) { _, enabled in
            if enabled { Task { await enhanceForStudioVoice() } }
        }
        .sheet(item: Binding(get: { shareURL.map(ShareURLItem.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Transport

    private var transportRow: some View {
        HStack(spacing: NSPSpacing.medium) {
            skipButton(seconds: -15, symbol: "gobackward.15")
            playPauseButton
            skipButton(seconds: 15, symbol: "goforward.15")

            VStack(spacing: NSPSpacing.extraSmall) {
                HStack {
                    Text(timeLabel(playback.playingURL == effectiveFileURL ? playback.currentTimeSeconds : 0))
                    Spacer()
                    Text(timeLabel(playback.durationSeconds))
                }
                .font(Typo.ui(10.5, .medium))
                .foregroundStyle(Palette.textTertiary)
            }

            speedButton
            trimToggleButton
            shareButton
        }
    }

    private var playPauseButton: some View {
        Button(action: togglePlayPause) {
            ZStack {
                Circle().fill(Palette.accent.foreground.gradient).frame(width: 52, height: 52)
                Image(systemName: isPlayingThisFile && playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlayingThisFile && playback.isPlaying ? "Pause" : "Play")
    }

    private var isPlayingThisFile: Bool { playback.playingURL == effectiveFileURL }

    private func togglePlayPause() {
        guard isPlayingThisFile else {
            playback.stopAtSeconds = isTrimming ? nil : (editState.hasTrim ? trimEndSecondsFromState : nil)
            let start = editState.hasTrim ? trimStartSecondsFromState : 0
            playback.play(fileURL: effectiveFileURL, fromOffsetSeconds: start)
            return
        }
        playback.togglePlayPause()
    }

    private func skipButton(seconds: TimeInterval, symbol: String) -> some View {
        Button {
            playback.skip(by: seconds)
        } label: {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Skip back 15 seconds" : "Skip forward 15 seconds")
    }

    private var speedButton: some View {
        Menu {
            ForEach(AudioPlaybackController.availableRates, id: \.self) { rate in
                Button {
                    playback.setRate(rate)
                } label: {
                    if playback.rate == rate {
                        Label(Self.speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.speedLabel(rate))
                    }
                }
            }
        } label: {
            Text(Self.speedLabel(playback.rate))
                .font(Typo.ui(12, .bold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, NSPSpacing.small)
                .padding(.vertical, 6)
                .background(Palette.fill, in: .capsule)
        }
        .accessibilityLabel("Playback speed, \(Self.speedLabel(playback.rate))")
    }

    private static func speedLabel(_ rate: Float) -> String {
        rate == 1.0 ? "1×" : "\(String(format: "%g", rate))×"
    }

    private var trimToggleButton: some View {
        Button {
            if !isTrimming {
                trimStartSeconds = editState.hasTrim ? trimStartSecondsFromState : 0
                trimEndSeconds = editState.hasTrim ? trimEndSecondsFromState : playback.durationSeconds
            }
            isTrimming.toggle()
        } label: {
            Image(systemName: "waveform").font(.system(size: 17)).foregroundStyle(
                isTrimming ? Palette.accent.foreground : Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trim audio")
        .accessibilityAddTraits(isTrimming ? .isSelected : [])
    }

    private var shareButton: some View {
        Button {
            Task { await prepareShare() }
        } label: {
            if isExportingClip {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up").font(.system(size: 17)).foregroundStyle(Palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isExportingClip)
        .accessibilityLabel("Share")
    }

    // MARK: - Waveform / scrubber

    @ViewBuilder
    private var scrubberOrWaveform: some View {
        if isTrimming, !peaks.isEmpty {
            WaveformTrimView(
                peaks: peaks, durationSeconds: playback.durationSeconds,
                currentTimeSeconds: playback.playingURL == effectiveFileURL ? playback.currentTimeSeconds : 0,
                trimStartSeconds: $trimStartSeconds, trimEndSeconds: $trimEndSeconds,
                onSeek: { playback.seek(toSeconds: $0) })
        } else {
            ProgressView(value: progress).tint(Palette.accent.foreground)
        }
    }

    // MARK: - Sample/second conversion

    private var trimStartSecondsFromState: TimeInterval { sampleToSeconds(editState.trimStartSample) }
    private var trimEndSecondsFromState: TimeInterval { sampleToSeconds(editState.trimEndSample) }

    private func sampleToSeconds(_ sample: Int64?) -> TimeInterval {
        guard let sample else { return 0 }
        return Double(sample) / Double(max(meeting.canonicalDuration.sampleRate, 1))
    }

    private func secondsToSample(_ seconds: TimeInterval) -> Int64 {
        Int64(seconds * Double(meeting.canonicalDuration.sampleRate))
    }

    // MARK: - Loading / persistence

    private func initialLoad() async {
        playback.load(fileURL: effectiveFileURL)
        guard let builtContainer = try? environment.makeMeetingContainer(meetingID: meeting.meetingID) else { return }
        container = builtContainer
        editState = AudioEditStateStore.load(container: builtContainer)
        peaks = (try? WaveformPeakExtractor().peaks(from: compositeAudioURL, bucketCount: 120)) ?? []
    }

    private func saveTrim() {
        editState.trimStartSample = secondsToSample(trimStartSeconds)
        editState.trimEndSample = secondsToSample(trimEndSeconds)
        isTrimming = false
        persistEditState()
    }

    private func clearTrim() {
        editState.trimStartSample = nil
        editState.trimEndSample = nil
        persistEditState()
    }

    private func setStudioVoice(_ enabled: Bool) {
        editState.studioVoiceEnabled = enabled
        persistEditState()
    }

    private func persistEditState() {
        guard let container else { return }
        try? AudioEditStateStore.save(editState, container: container)
    }

    private func enhanceForStudioVoice() async {
        guard let container else { return }
        let enhancedURL = container.derivedDirectoryURL.appendingPathComponent("studio.m4a")
        guard !FileManager.default.fileExists(atPath: enhancedURL.path) else { return }
        isEnhancing = true
        defer { isEnhancing = false }
        do {
            try StudioVoiceEnhancer().enhance(sourceURL: compositeAudioURL, to: enhancedURL)
        } catch {
            enhanceError = "\(error)"
            editState.studioVoiceEnabled = false
            persistEditState()
        }
    }

    private func prepareShare() async {
        guard editState.hasTrim, let container else {
            shareURL = compositeAudioURL
            return
        }
        isExportingClip = true
        defer { isExportingClip = false }
        let clipURL = container.derivedDirectoryURL.appendingPathComponent("shared_clip.m4a")
        do {
            try AudioClipExporter().exportClip(
                from: effectiveFileURL, startSample: secondsToSample(trimStartSecondsFromState),
                endSample: secondsToSample(trimEndSecondsFromState), to: clipURL)
            shareURL = clipURL
        } catch {
            exportError = "\(error)"
        }
    }
}

/// The trim/Studio-Voice controls beneath the waveform — split out of
/// `AudioPlayerCard` purely to keep that type under this repo's 250-line
/// type-body budget.
private struct AudioEditControlsRow: View {
    let isTrimming: Bool
    let hasTrim: Bool
    let trimStartSeconds: TimeInterval
    let trimEndSeconds: TimeInterval
    let savedTrimStartSeconds: TimeInterval
    let savedTrimEndSeconds: TimeInterval
    let studioVoiceEnabled: Bool
    let isEnhancing: Bool
    let timeLabel: (TimeInterval) -> String
    let onCancelTrim: () -> Void
    let onSaveTrim: () -> Void
    let onClearTrim: () -> Void
    let onSetStudioVoice: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            if isTrimming {
                HStack {
                    Text("\(timeLabel(trimStartSeconds)) – \(timeLabel(trimEndSeconds))")
                        .font(Typo.ui(11, .semibold)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Cancel", action: onCancelTrim).font(Typo.ui(12, .semibold))
                    Button("Save Trim", action: onSaveTrim)
                        .font(Typo.ui(12, .bold)).foregroundStyle(Palette.accent.foreground)
                }
            } else if hasTrim {
                HStack {
                    Text("Trimmed \(timeLabel(savedTrimStartSeconds)) – \(timeLabel(savedTrimEndSeconds))")
                        .font(Typo.ui(11, .semibold)).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Button("Clear", action: onClearTrim)
                        .font(Typo.ui(11, .semibold)).foregroundStyle(Palette.danger.foreground)
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { studioVoiceEnabled }, set: onSetStudioVoice)) {
                    Text("Studio Voice").font(Typo.ui(12.5, .semibold))
                }
                .toggleStyle(.switch)
                .tint(Palette.accent.foreground)
                if isEnhancing {
                    ProgressView().padding(.leading, NSPSpacing.small)
                }
            }
        }
    }
}

private struct ShareURLItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
