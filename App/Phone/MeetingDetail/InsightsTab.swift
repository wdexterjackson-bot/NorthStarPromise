import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Insights tab — generated summary/recap bullets (`NSP-082`'s
/// thin slice: `.executiveSummary` only this pass) and `Decision`s merged
/// into one list, ordered by where each first happened in the meeting
/// (`CommitmentItem.firstSample`) — not two separately-headed sections.
/// This is the user's own framing, verbatim: "insights (things learned or
/// decisions made)" is one category, not two (docs/09-BACKLOG.md,
/// "rescoping the meeting-organization data model"). The tab keeps its
/// short "Insights" label (`MeetingDetailView.Tab`'s 8-tab segmented
/// control has no room for a longer one) — only the content merges. Both
/// tap-to-seek into the meeting's stitched composite (`playback`, shared
/// with the Audio and Transcript tabs by `MeetingDetailView`) at their
/// first evidence span, same shape as `TranscriptTab`'s.
@MainActor
struct InsightsTab: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let playback: AudioPlaybackController
    let compositeAudioURL: URL?

    @State private var items: [CommitmentItem] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            if let loadError {
                Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Nothing yet", systemImage: "lightbulb",
                    description: Text("What was learned or decided is generated during processing."))
            } else {
                ForEach(items) { item in
                    switch item {
                    case .decision(let decision):
                        DecisionRow(decision: decision) { seek(to: decision.evidence.first) }
                    case .insight(let insight):
                        InsightRow(insight: insight) { seek(to: insight.evidence.first) }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func seek(to evidence: EvidenceSpan?) {
        guard let compositeAudioURL, let startSample = evidence?.sampleRange.startSample else { return }
        let offsetSeconds = TimeInterval(startSample) / TimeInterval(meeting.canonicalDuration.sampleRate)
        playback.play(fileURL: compositeAudioURL, fromOffsetSeconds: offsetSeconds)
    }

    private func load() async {
        do {
            async let fetchedInsights = environment.insightRepository.fetchAll(meetingID: meeting.meetingID)
            async let fetchedDecisions = environment.decisionRepository.fetchAll(meetingID: meeting.meetingID)
            let combined =
                (try await fetchedDecisions).map(CommitmentItem.decision)
                + (try await fetchedInsights).map(CommitmentItem.insight)
            items = combined.sorted { ($0.firstSample ?? .max) < ($1.firstSample ?? .max) }
        } catch {
            loadError = "\(error)"
        }
    }
}

/// One merged list of "things learned or decided" — a `Decision` and an
/// `Insight` share no common protocol in `NSPCore`, so this is the local
/// wrapper `InsightsTab` sorts and renders from, not a new domain type.
private enum CommitmentItem: Identifiable {
    case decision(Decision)
    case insight(Insight)

    var id: String {
        switch self {
        case .decision(let decision): return decision.decisionID.rawValue.uuidString
        case .insight(let insight): return insight.insightID.rawValue.uuidString
        }
    }

    /// `nil` sorts last — an ungrounded item has no "when" to anchor on.
    var firstSample: Int64? {
        switch self {
        case .decision(let decision): return decision.evidence.first?.sampleRange.startSample
        case .insight(let insight): return insight.evidence.first?.sampleRange.startSample
        }
    }
}

private struct DecisionRow: View {
    let decision: Decision
    let onSeek: () -> Void

    var body: some View {
        Button(action: onSeek) {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                Text(decision.text).font(Typo.ui(14, .medium)).foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                if !decision.evidence.isEmpty {
                    Text("\(decision.evidence.count) source\(decision.evidence.count == 1 ? "" : "s")")
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        }
        .buttonStyle(.plain)
        .disabled(decision.evidence.isEmpty)
    }
}

private struct InsightRow: View {
    let insight: Insight
    let onSeek: () -> Void

    private var claimBadge: (label: String, tint: Color) {
        switch insight.claimKind {
        case .said: return ("Said", Palette.textSecondary)
        case .agreed: return ("Agreed", Palette.success.foreground)
        case .aiSuggests: return ("AI suggests", Palette.accent.foreground)
        }
    }

    var body: some View {
        Button(action: onSeek) {
            VStack(alignment: .leading, spacing: NSPSpacing.small) {
                Text(insight.text).font(Typo.ui(14, .medium)).foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: NSPSpacing.small) {
                    NSPStatusBadge(symbolName: "sparkles", label: claimBadge.label, tint: claimBadge.tint)
                    if !insight.evidence.isEmpty {
                        Text("\(insight.evidence.count) source\(insight.evidence.count == 1 ? "" : "s")")
                            .font(Typo.ui(11.5, .medium))
                            .foregroundStyle(Palette.textTertiary)
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
