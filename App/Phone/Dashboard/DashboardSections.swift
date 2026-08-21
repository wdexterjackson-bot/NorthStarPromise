import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The Dashboard's collapsing header (`DASHBOARD_SPEC.md` §5.1) — eyebrow
/// date, Instrument Serif title (the one place per screen that face is
/// allowed — spec §2.3), and a subline. `isCollapsed` is driven by the
/// parent's scroll offset (`DashboardView`'s own `ScrollView` reader),
/// since a single view can't know its own scroll position.
struct DashboardHeaderSection: View {
    let dateText: String
    let headline: String
    let isCollapsed: Bool

    var body: some View {
        if isCollapsed {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today").font(Typo.ui(16, .extrabold))
                    Text(dateText).font(Typo.ui(11.5, .semibold)).foregroundStyle(Palette.textQuaternary)
                }
                Spacer()
            }
            .padding(.vertical, NSPSpacing.small)
            .animation(.easeInOut(duration: 0.12), value: isCollapsed)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateText.uppercased())
                    .font(Typo.ui(10.5, .extrabold, relativeTo: .caption2))
                    .tracking(0.16 * 10.5)
                    .foregroundStyle(Palette.textQuaternary)
                Text("Today").font(Typo.display(40))
                Text(headline).font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textTertiary)
            }
            .animation(.easeInOut(duration: 0.12), value: isCollapsed)
        }
    }
}

/// The Recall search field (§5.2) — not a real filter, a semantic-search
/// entry point. Routes to the `Ask` tab rather than duplicating its logic
/// (Dashboard scope plan's Q2 resolution: Ask keeps its own tab *and* the
/// Dashboard gets this field).
struct DashboardRecallField: View {
    let corpusCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(Palette.textQuaternary)
                Text("Ask across \(corpusCount) meetings…")
                    .font(Typo.ui(13.5, .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("RECALL")
                    .font(Typo.ui(9.5, .extrabold, relativeTo: .caption2))
                    .tracking(0.08 * 9.5)
                    .foregroundStyle(Palette.accent.foreground)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// One row of "The day, threaded" (§5.4) — a timeline node rather than a
/// plain list row: a thread-colored dot, a connector line, and a
/// continuity-fact subline (never just a time or attendee count — the
/// model already guarantees this, `AgendaItem.continuityFact`'s own doc
/// comment).
struct DashboardAgendaRow: View {
    let item: AgendaItem
    let isLast: Bool

    private var dotColor: Color {
        guard let thread = item.thread else { return Palette.threadInactive }
        return Palette.threadSlots[thread.colorSlot]
    }

    private var timeColor: Color {
        switch item.state {
        case .past: return Palette.textMuted
        case .live: return Palette.nowMarker
        case .next, .future: return Palette.textPrimary
        }
    }

    private var titleColor: Color {
        item.state == .past ? Palette.textQuaternary : Palette.textPrimary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(item.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Typo.ui(11, .bold))
                .foregroundStyle(timeColor)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            VStack(spacing: 0) {
                ThreadDot(color: dotColor, isCurrent: item.state == .live || item.state == .next, size: 9)
                if !isLast {
                    Rectangle().fill(Palette.divider).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Typo.ui(13.5, .bold)).foregroundStyle(titleColor).lineLimit(1)
                Text(item.continuityFact)
                    .font(Typo.ui(11, .semibold))
                    .foregroundStyle(item.recapReady ? Palette.success.foreground : dotColor)
            }
            .padding(.bottom, 16)
        }
    }
}

/// One card in "Threads in motion" (§5.5/§4.5).
struct ThreadMotionCard: View {
    let card: ThreadCard
    let action: () -> Void

    private var statusStyle: StatusChip.Style {
        switch card.status {
        case .atRisk: return .danger
        case .decisionDue: return .warn
        case .dormant: return .neutral
        case .onTrack, .closed: return .success
        }
    }

    private var statusLabel: String {
        switch card.status {
        case .onTrack: return "On track"
        case .decisionDue: return "Decision due"
        case .atRisk: return "At risk"
        case .dormant: return "Dormant"
        case .closed: return "Closed"
        }
    }

    private var meetingCountCaption: String {
        let since = card.sinceDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(card.meetingCount) meeting\(card.meetingCount == 1 ? "" : "s") · since \(since)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ThreadRail(color: Palette.threadSlots[card.colorSlot], height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name).font(Typo.ui(13.5, .extrabold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(meetingCountCaption)
                        .font(Typo.ui(11, .semibold))
                        .foregroundStyle(Palette.textQuaternary)
                }
                Spacer(minLength: 0)
                StatusChip(statusLabel, style: statusStyle)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

/// One row of "Needs you" (§5.6) — the provenance line is mandatory: it
/// always answers "where did this come from" (`NeedsYouItem.provenance`).
struct NeedsYouRow: View {
    let item: NeedsYouItem
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: onComplete) {
                Circle().strokeBorder(Palette.borderStrong, lineWidth: 1.6).frame(width: 19, height: 19)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text).font(Typo.ui(13, .bold)).foregroundStyle(Palette.textPrimary)
                if !item.provenance.isEmpty {
                    Text(item.provenance).font(Typo.ui(10.5, .semibold)).foregroundStyle(Palette.textQuaternary)
                }
            }
            Spacer(minLength: 0)
            StatusChip(item.statusChipLabel, style: item.isOverdue ? .danger : .neutral)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// One "what your history noticed" card (§5.7). High severity gets a
/// tinted card; normal severity stays flat with a colored lead clause.
struct DashboardSignalCard: View {
    let signal: DashboardSignal

    private var iconName: String {
        switch signal.kind {
        case .unresolvedLoop: return "exclamationmark.triangle"
        case .collision: return "chart.line.uptrend.xyaxis"
        case .personPattern: return "person.badge.plus"
        case .overdueCommitment: return "clock"
        case .dormantThread: return "moon.zzz"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17))
                .foregroundStyle(signal.severity == .high ? Palette.warn.foreground : Palette.accent.foreground)
            Text(signal.body)
                .font(Typo.ui(13, .medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            signal.severity == .high ? Palette.warn.background : Palette.surface,
            in: .rect(cornerRadius: Metrics.radiusCard - 1, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusCard - 1, style: .continuous)
                .strokeBorder(signal.severity == .high ? Palette.warn.border : Palette.border, lineWidth: 1)
        )
    }
}

/// The Next Up hero card (§5.3) — the screen's single most prominent card.
/// Block A is the meeting header; Block B is the "carried in from your
/// history" prep panel, which renders **fewer than three rows** rather than
/// padding when fewer qualify (spec's own rule — `NextUpBrief.prepRows`'s
/// doc comment).
struct NextUpCard: View {
    let brief: NextUpBrief
    let onOpenBrief: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                headerRow
                Text(brief.meeting.title)
                    .font(Typo.ui(19, .extrabold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                metaRow
            }
            .padding(15)

            if !brief.prepRows.isEmpty {
                Divider().overlay(Palette.divider)
                VStack(alignment: .leading, spacing: 11) {
                    Text("CARRIED IN FROM YOUR HISTORY")
                        .font(Typo.ui(10, .extrabold, relativeTo: .caption2))
                        .tracking(0.14 * 10)
                        .foregroundStyle(Palette.textQuaternary)
                    ForEach(Array(brief.prepRows.enumerated()), id: \.offset) { _, row in
                        PrepRowView(row: row)
                    }
                    actionRow
                }
                .padding(13)
                .background(Palette.surfaceSunken)
            } else {
                actionRow.padding(.horizontal, 15).padding(.bottom, 15)
            }
        }
        .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusHeroPhone, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusHeroPhone, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 9) {
            if let thread = brief.meeting.thread {
                ThreadDot(color: Palette.threadSlots[thread.colorSlot])
                Text(thread.name.uppercased())
                    .font(Typo.ui(10, .extrabold, relativeTo: .caption2))
                    .foregroundStyle(Palette.threadSlots[thread.colorSlot])
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("in \(brief.minutesUntil) min")
                .font(Typo.ui(11, .extrabold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Palette.fill, in: .capsule)
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Text(brief.meeting.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Typo.ui(12.5, .bold))
            Text("–")
            Text(brief.meeting.end.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Typo.ui(12.5, .bold))
        }
        .foregroundStyle(Palette.textTertiary)
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            PrimaryButton("Open the brief", symbolName: "doc.text", action: onOpenBrief)
            SecondaryButton("Join", symbolName: "video", action: onJoin)
        }
    }
}

private struct PrepRowView: View {
    let row: PrepRow

    private var tint: SemanticTint {
        switch row.kind {
        case .owed: return Palette.warn
        case .unresolved: return Palette.accent
        case .expectAgain:
            return SemanticTint(foreground: Palette.textSecondary, background: Palette.fill, border: Palette.border)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            TintedIconTile(symbolName: iconName, tint: tint)
            (Text(row.leadClause + " ").font(Typo.ui(12.5, .extrabold)).foregroundStyle(tint.foreground)
                + Text(row.body).font(Typo.ui(12.5, .regular)).foregroundStyle(Palette.textSecondary))
        }
    }

    private var iconName: String {
        switch row.kind {
        case .owed: return "clock"
        case .unresolved: return "arrow.uturn.left"
        case .expectAgain: return "smallcircle.filled.circle"
        }
    }
}
