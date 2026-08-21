import AVFoundation
import Observation

/// Plays a file — the meeting's stitched composite (`SegmentStitcher`), or
/// (fallback) a single raw segment file — identically, via `AVAudioPlayer`.
/// One shared instance lives on `MeetingDetailView` and is passed down to
/// the Audio/Transcript/Insights tabs, so switching tabs mid-playback
/// doesn't stop it and every tab seeks the same absolute meeting timeline.
@MainActor
@Observable
final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private(set) var isPlaying = false
    private(set) var currentTimeSeconds: TimeInterval = 0
    private(set) var durationSeconds: TimeInterval = 0
    private(set) var rate: Float = 1.0
    /// Voice Memos' own offered speeds — every value works with
    /// `AVAudioPlayer.enableRate`, no separate pitch-correction concern
    /// since this app never needs music-quality time-stretching.
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    /// When set, playback started via `play(fileURL:fromOffsetSeconds:)`
    /// pauses itself the moment `currentTimeSeconds` reaches this point —
    /// the Audio tab's trim preview ("hear just the selected range")
    /// without needing a separately exported clip for playback (export is
    /// still real, for Share — `AudioClipExporter`).
    var stopAtSeconds: TimeInterval?

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    /// Loads `fileURL` (populating `durationSeconds` for a scrubber) without
    /// starting playback. A no-op if `fileURL` is already loaded — safe to
    /// call from a view's `.task(id:)` every time it appears.
    func load(fileURL: URL) {
        guard playingURL != fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path),
            let newPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        else { return }
        stop()
        newPlayer.delegate = self
        newPlayer.enableRate = true
        newPlayer.rate = rate
        newPlayer.prepareToPlay()
        player = newPlayer
        playingURL = fileURL
        durationSeconds = newPlayer.duration
    }

    /// Loads `fileURL` if it isn't already loaded, seeks to `offset`, and
    /// plays. Reusing the same `AVAudioPlayer` when `fileURL` hasn't changed
    /// (e.g. seeking to a different marker within the same composite) avoids
    /// a needless reload.
    func play(fileURL: URL, fromOffsetSeconds offset: TimeInterval = 0) {
        load(fileURL: fileURL)
        guard let player else { return }
        player.currentTime = max(0, min(offset, player.duration))
        currentTimeSeconds = player.currentTime
        player.play()
        isPlaying = true
        startProgressPolling()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopProgressPolling()
        } else {
            player.play()
            isPlaying = true
            startProgressPolling()
        }
    }

    func seek(toSeconds seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        currentTimeSeconds = player.currentTime
    }

    /// Voice Memos' skip-15 buttons — clamped to the file's bounds rather
    /// than letting `AVAudioPlayer.currentTime` go negative or past
    /// `duration`, either of which is undefined behavior for that API.
    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        seek(toSeconds: player.currentTime + seconds)
    }

    /// `AVAudioPlayer.rate` only takes effect with `enableRate` set at load
    /// time (already done in `load`), so this also re-applies it to
    /// whichever player is current — cycling speed mid-playback doesn't
    /// need a reload.
    func setRate(_ newRate: Float) {
        rate = newRate
        player?.rate = newRate
    }

    func stop() {
        stopProgressPolling()
        player?.stop()
        player = nil
        playingURL = nil
        isPlaying = false
        currentTimeSeconds = 0
        durationSeconds = 0
        stopAtSeconds = nil
    }

    /// 10fps poll to drive a scrubber — `AVAudioPlayer` has no progress
    /// callback of its own, same tradeoff `RecordingSession`'s elapsed-time
    /// timer already documents.
    private func startProgressPolling() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentTimeSeconds = self.player?.currentTime ?? 0
                if let stopAtSeconds = self.stopAtSeconds, self.currentTimeSeconds >= stopAtSeconds {
                    self.player?.pause()
                    self.isPlaying = false
                    self.stopProgressPolling()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopProgressPolling() {
        progressTask?.cancel()
        progressTask = nil
    }

    // The `player` parameter isn't forwarded into the hop — comparing it
    // against `self.player` on the MainActor side would send a
    // non-`Sendable` `AVAudioPlayer` across isolation. Only one player is
    // ever active at a time (`play()` replaces it synchronously), so an
    // unconditional flip is equivalent and avoids that data race.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopProgressPolling()
        }
    }
}
