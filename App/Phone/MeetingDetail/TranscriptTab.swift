import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Transcript tab — the canonical batch pass's output
/// (`NSP-073`), real for the first time this pass. Tap-a-turn-to-seek plays
/// the meeting's stitched composite (`playback`, shared with the Audio and
/// Insights tabs by `MeetingDetailView`) at the turn's absolute offset — no
/// per-segment lookup needed since the composite is one continuous timeline.
@MainActor
struct TranscriptTab: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let playback: AudioPlaybackController
    let compositeAudioURL: URL?

    @State private var turns: [TranscriptTurn] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            } else if turns.isEmpty {
                ContentUnavailableView(
                    "No transcript yet", systemImage: "text.bubble",
                    description: Text("Transcription runs after processing completes."))
            } else {
                ForEach(turns) { turn in
                    TranscriptTurnRow(turn: turn) { seek(to: turn) }
                }
            }
        }
        .task { await load() }
    }

    private func seek(to turn: TranscriptTurn) {
        guard let compositeAudioURL, let startSample = turn.tokens.first?.startSample else { return }
        let offsetSeconds = TimeInterval(startSample) / TimeInterval(meeting.canonicalDuration.sampleRate)
        playback.play(fileURL: compositeAudioURL, fromOffsetSeconds: offsetSeconds)
    }

    private func load() async {
        do {
            turns = try await environment.transcriptTurnRepository.fetchAll(meetingID: meeting.meetingID)
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct TranscriptTurnRow: View {
    let turn: TranscriptTurn
    let onSeek: () -> Void

    // Speaker attribution isn't built yet (diarization is out of this
    // pass's scope — `docs/09` NSP-075/076) — every `turn.personID` is
    // `nil` today, so this row shows text only rather than a placeholder
    // that would look broken once it's real.
    private var text: String { turn.tokens.map(\.text).joined(separator: " ") }

    var body: some View {
        Button(action: onSeek) {
            Text(text)
                .font(.body)
                .foregroundStyle(NSPColor.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nspCard()
        }
        .buttonStyle(.plain)
    }
}
