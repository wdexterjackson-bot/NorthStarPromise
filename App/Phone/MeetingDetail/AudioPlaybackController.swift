import AVFoundation
import NSPCore
import Observation

/// Plays one closed segment file at a time via `AVAudioPlayer`. Segments
/// are separate immutable `.m4a` files (Invariant I3) rather than one
/// continuous recording, so this deliberately does not attempt gapless
/// cross-segment playback — switching segments is a new `AVAudioPlayer`
/// load, same as switching tracks.
@MainActor
@Observable
final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var playingSegmentID: SegmentID?
    private(set) var isPlaying = false

    private var player: AVAudioPlayer?

    func play(segment: Segment, fromOffsetSeconds offset: TimeInterval = 0) {
        guard let url = segment.localURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.currentTime = max(0, offset)
            newPlayer.play()
            player = newPlayer
            playingSegmentID = segment.segmentID
            isPlaying = true
        } catch {
            player = nil
            playingSegmentID = nil
            isPlaying = false
        }
    }

    func togglePlayPause(segment: Segment) {
        if playingSegmentID == segment.segmentID, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        play(segment: segment)
    }

    func stop() {
        player?.stop()
        player = nil
        playingSegmentID = nil
        isPlaying = false
    }

    // The `player` parameter isn't forwarded into the hop — comparing it
    // against `self.player` on the MainActor side would send a
    // non-`Sendable` `AVAudioPlayer` across isolation. Only one player is
    // ever active at a time (`play()` replaces it synchronously), so an
    // unconditional flip is equivalent and avoids that data race.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
