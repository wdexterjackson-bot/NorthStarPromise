import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The iPad Dashboard's sidebar (`DASHBOARD_SPEC.md` §4.1) — brand, Recall
/// field, a restricted vertical nav list (Actions/Threads/People/Calendar
/// — the areas not already reachable from `PadRootView`'s top header),
/// Today's Agenda, and the pinned capture control. Only shown while
/// Dashboard is the selected top-header area; every other area's content
/// takes the whole leading column instead (`PadRootView.leadingColumn`).
struct PadDashboardSidebar: View {
    let model: DashboardModel?
    let selectedArea: AppTab
    /// 304pt at/above 1000pt window width, 280pt below it (§4.7).
    let width: CGFloat
    let onSelectArea: (AppTab) -> Void
    let onSelectMeeting: (MeetingID) -> Void
    let onRecall: () -> Void
    let onStartMeeting: () -> Void
    let onStartNotesOnly: () -> Void
    let onStartMentalNote: () -> Void
    let onImportAudio: () -> Void
    let onAddAgendaItem: () -> Void

    /// Everything the top header doesn't already carry
    /// (`PadRootView.headerAreas`).
    private static let sidebarAreas: [AppTab] = [.actions, .threads, .people, .calendar]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                brand
                DashboardRecallField(corpusCount: model?.corpusCount ?? 0, action: onRecall)
                    .padding(.top, 18)
                navList.padding(.top, 20)
            }
            .padding(.horizontal, Metrics.screenMarginPadSidebar)
            .padding(.top, 24)

            Divider().overlay(Palette.divider).padding(.top, 22).padding(.horizontal, 6)

            agendaSection
                .padding(.horizontal, Metrics.screenMarginPadSidebar)
                .padding(.top, 18)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                DashboardNotesOnlyButton(action: onStartNotesOnly)
                DashboardCaptureButton(
                    isRecording: false, onStartMeeting: onStartMeeting, onStartMentalNote: onStartMentalNote,
                    onImportAudio: onImportAudio
                )
                DashboardBrainDumpButton(action: onStartMentalNote)
            }
            .padding(.bottom, 28)
        }
        .frame(width: width)
        .background(Palette.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 1) }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.textPrimary)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "square.stack.3d.up").font(.system(size: 16)).foregroundStyle(Palette.canvas))
            Text("North-Star Promise").font(Typo.ui(15, .extrabold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
        }
    }

    private var navList: some View {
        VStack(spacing: 2) {
            ForEach(Self.sidebarAreas, id: \.self) { area in
                NavRow(area: area, count: navCount(for: area), isSelected: area == selectedArea) {
                    onSelectArea(area)
                }
            }
        }
    }

    private func navCount(for area: AppTab) -> Int? {
        guard let model else { return nil }
        switch area {
        case .threads: return model.navCounts.openThreads
        case .actions: return model.navCounts.openActionsIOwe
        default: return nil
        }
    }

    @ViewBuilder
    private var agendaSection: some View {
        HStack {
            Text("TODAY'S AGENDA")
                .font(Typo.ui(10, .extrabold, relativeTo: .caption2))
                .tracking(0.14 * 10)
                .foregroundStyle(Palette.textQuaternary)
            Spacer()
            Button(action: onAddAgendaItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.accent.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to today's agenda")
        }
        if let agenda = model?.agenda, !agenda.isEmpty {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(agenda) { item in
                        Button {
                            onSelectMeeting(item.meetingID)
                        } label: {
                            PadAgendaRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            }
        } else {
            Text("Nothing scheduled. Tap Start capture for an ad-hoc meeting.")
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textQuaternary)
                .padding(.top, 10)
        }
    }
}

private struct NavRow: View {
    let area: AppTab
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: area.symbolName).font(.system(size: 15))
                Text(area.title).font(Typo.ui(13.5, isSelected ? .extrabold : .medium))
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").font(Typo.ui(11, isSelected ? .extrabold : .bold))
                }
            }
            .foregroundStyle(isSelected ? Palette.accent.foreground : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                isSelected ? Palette.accent.background : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The sidebar's agenda row (§4.2) — a thread rail rather than the phone
/// timeline's dot, per the spec's own distinct iPad row anatomy.
private struct PadAgendaRow: View {
    let item: AgendaItem

    private var railColor: Color {
        guard let thread = item.thread else { return Palette.threadInactive }
        return Palette.threadSlots[thread.colorSlot]
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(item.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(Typo.ui(11, .bold))
                .foregroundStyle(item.state == .past ? Palette.textMuted : Palette.textPrimary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            ThreadRail(color: railColor, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Typo.ui(12.5, item.state == .past ? .medium : .bold))
                    .foregroundStyle(item.state == .past ? Palette.textQuaternary : Palette.textPrimary)
                    .lineLimit(1)
                Text(item.continuityFact).font(Typo.ui(10.5, .semibold)).foregroundStyle(railColor).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            item.state == .next || item.state == .live ? Palette.fill : Color.clear,
            in: .rect(cornerRadius: 9, style: .continuous))
    }
}

/// The iPad Dashboard's main column (§4.3–§4.6) — occupies `PadRootView`'s
/// detail column whenever nothing is selected and the Dashboard area is
/// active (selecting a meeting swaps that same column to the real
/// `MeetingDetailView`/canvas, this app's existing two-column pattern).
struct PadDashboardMainColumn: View {
    let model: DashboardModel?
    /// Below 1000pt window width (§4.7): "Threads in motion" drops to 2
    /// columns showing the top 2, and "Captured this morning" stacks to 1
    /// column.
    let isCompactWidth: Bool
    let onSelectMeeting: (MeetingID) -> Void
    let onSelectArea: (AppTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let brief = model?.nextUp {
                    NextUpCard(
                        brief: brief, onOpenBrief: { onSelectMeeting(brief.meeting.meetingID) },
                        onJoin: { onSelectMeeting(brief.meeting.meetingID) })
                } else if model != nil {
                    ContentUnavailableView(
                        "That's the day", systemImage: "checkmark.circle",
                        description: Text("Nothing else scheduled today."))
                }
                threadsInMotion
                HStack(alignment: .top, spacing: 20) {
                    needsYou
                    signals
                }
                capturedToday
            }
            .padding(.top, 38)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(Typo.ui(10.5, .extrabold, relativeTo: .caption2))
                .tracking(0.16 * 10.5)
                .foregroundStyle(Palette.textQuaternary)
            Text("Today").font(Typo.display(42))
        }
    }

    private var threadColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: isCompactWidth ? 2 : 3)
    }

    @ViewBuilder
    private var threadsInMotion: some View {
        if let cards = model?.threadsInMotion, !cards.isEmpty {
            let shown = isCompactWidth ? Array(cards.prefix(2)) : cards
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Threads in motion", trailingAction: ("All \(cards.count)", { onSelectArea(.threads) }))
                LazyVGrid(columns: threadColumns, spacing: 14) {
                    ForEach(shown) { card in
                        Button {
                            onSelectArea(.threads)
                        } label: {
                            ThreadMotionCard(card: card, action: {})
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var needsYou: some View {
        if let needsYou = model?.needsYou, !needsYou.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    "Needs you",
                    inlineChip: needsYou.overdueCount > 0 ? ("\(needsYou.overdueCount) overdue", .danger) : nil,
                    trailingAction: ("\(needsYou.openCount) open", { onSelectArea(.actions) }))
                VStack(spacing: 0) {
                    ForEach(needsYou.items) { item in NeedsYouRow(item: item, onComplete: {}) }
                }
                .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var signals: some View {
        if let signals = model?.signals, !signals.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeader("What your history noticed")
                ForEach(signals) { DashboardSignalCard(signal: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capturedColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: isCompactWidth ? 1 : 2)
    }

    @ViewBuilder
    private var capturedToday: some View {
        if let cards = model?.capturedToday, !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Captured this morning")
                LazyVGrid(columns: capturedColumns, spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            onSelectMeeting(card.meetingID)
                        } label: {
                            RecapCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RecapCardView: View {
    let card: RecapCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let thread = card.thread {
                    ThreadDot(color: Palette.threadSlots[thread.colorSlot])
                }
                Text(card.title).font(Typo.ui(13.5, .extrabold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(card.durationMinutes) min").font(Typo.ui(11, .semibold)).foregroundStyle(Palette.textQuaternary)
            }
            if !card.headline.isEmpty {
                Text(card.headline).font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
    }
}
