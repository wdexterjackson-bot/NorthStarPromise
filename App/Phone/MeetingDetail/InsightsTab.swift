import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Insights tab — generated summary/recap bullets (`NSP-082`'s
/// thin slice: `.executiveSummary` only this pass). Tap-to-seek plays the
/// meeting's stitched composite (`playback`, shared with the Audio and
/// Transcript tabs by `MeetingDetailView`) at the insight's first evidence
/// span, same shape as `TranscriptTab`'s.
@MainActor
struct InsightsTab: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let playback: AudioPlaybackController
    let compositeAudioURL: URL?

    @State private var insights: [Insight] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(NSPColor.secondaryText)
            } else if insights.isEmpty {
                ContentUnavailableView(
                    "No insights yet", systemImage: "lightbulb",
                    description: Text("Insights are generated during processing."))
            } else {
                ForEach(insights) { insight in
                    InsightRow(insight: insight) { seek(to: insight) }
                }
            }
        }
        .task { await load() }
    }

    private func seek(to insight: Insight) {
        guard let compositeAudioURL, let startSample = insight.evidence.first?.sampleRange.startSample else { return }
        let offsetSeconds = TimeInterval(startSample) / TimeInterval(meeting.canonicalDuration.sampleRate)
        playback.play(fileURL: compositeAudioURL, fromOffsetSeconds: offsetSeconds)
    }

    private func load() async {
        do {
            insights = try await environment.insightRepository.fetchAll(meetingID: meeting.meetingID)
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct InsightRow: View {
    let insight: Insight
    let onSeek: () -> Void

    private var claimBadge: (label: String, tint: Color) {
        switch insight.claimKind {
        case .said: return ("Said", NSPColor.statusNeutral)
        case .agreed: return ("Agreed", NSPColor.statusSuccess)
        case .aiSuggests: return ("AI suggests", NSPColor.statusInProgress)
        }
    }

    var body: some View {
        Button(action: onSeek) {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                Text(insight.text).font(.body).foregroundStyle(NSPColor.primaryText).multilineTextAlignment(.leading)
                HStack(spacing: NSPSpacing.small) {
                    NSPStatusBadge(symbolName: "sparkles", label: claimBadge.label, tint: claimBadge.tint)
                    if !insight.evidence.isEmpty {
                        Text("\(insight.evidence.count) source\(insight.evidence.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(NSPColor.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        }
        .buttonStyle(.plain)
        .disabled(insight.evidence.isEmpty)
    }
}
