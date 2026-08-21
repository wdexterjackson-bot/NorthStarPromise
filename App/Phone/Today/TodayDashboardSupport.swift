import NSPCore
import NSPDesignSystem
import SwiftUI

/// The post-recording sheet chain `TodayView` shows over itself — title
/// prompt first, calendar prompt second (never both at once; see
/// `RecordingSession.stop()`'s doc comment for why the calendar prompt
/// waits). Pulled out of `TodayView.body` itself only to keep that type
/// under the project's type-body-length budget; owns no state of its own.
struct TodayPromptSheets: ViewModifier {
    let session: RecordingSession
    let environment: AppEnvironment
    let onDismiss: () async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(
                item: Binding(
                    get: { session.pendingTitleMeeting },
                    set: { newValue in
                        if newValue == nil, let meeting = session.pendingTitleMeeting {
                            session.dismissTitlePrompt(meeting: meeting)
                        }
                    })
            ) { meeting in
                MeetingTitlePromptView(
                    meeting: meeting, environment: environment,
                    onSave: { updated, options in
                        session.dismissTitlePrompt(meeting: updated, options: options)
                        Task { await onDismiss() }
                    },
                    onDelete: {
                        session.discardPendingTitleMeeting()
                        Task {
                            try? await environment.deleteMeeting(meeting.meetingID)
                            await onDismiss()
                        }
                    })
            }
            .sheet(
                item: Binding(
                    get: { session.pendingCalendarMeeting },
                    set: { newValue in if newValue == nil { session.dismissCalendarPrompt() } })
            ) { meeting in
                CalendarEventConfirmationView(
                    meeting: meeting, environment: environment,
                    onDone: {
                        session.dismissCalendarPrompt()
                        Task { await onDismiss() }
                    })
            }
    }
}

/// Surfaces `IntelligenceCoordinator.status` — before this existed, nothing
/// in the UI ever read that property, so a meeting that finished recording
/// but degraded (no speech recognized, on-device summarizer unavailable) or
/// failed outright looked identical to one that simply hadn't been touched
/// yet: silent, with no way for the user to tell what happened. Attached at
/// the root (`PhoneRootView`/`PadRootView`), not any one screen, since
/// processing can finish while the user is on any tab.
struct IntelligenceStatusOverlay: ViewModifier {
    let environment: AppEnvironment
    @State private var dismissedStatus: IntelligenceProcessingStatus?

    func body(content: Content) -> some View {
        let status = environment.intelligenceCoordinator.status
        VStack(spacing: 0) {
            if status != .idle, status != dismissedStatus {
                IntelligenceStatusBanner(status: status, onDismiss: { dismissedStatus = status })
            }
            content
        }
        .animation(.snappy(duration: 0.25), value: status)
    }
}

private struct IntelligenceStatusBanner: View {
    let status: IntelligenceProcessingStatus
    let onDismiss: () -> Void

    private struct Appearance {
        let symbol: String
        let text: String
        let tint: Color
    }

    private var appearance: Appearance? {
        switch status {
        case .idle: return nil
        case .processing:
            return Appearance(
                symbol: "gearshape.2", text: "Processing your meeting — transcribing and summarizing…",
                tint: Palette.accent.foreground)
        case .succeeded:
            return Appearance(
                symbol: "checkmark.circle.fill",
                text: "Meeting processed — transcript, summary, and action items are ready.",
                tint: Palette.success.foreground)
        case .degraded(let reason):
            return Appearance(symbol: "exclamationmark.triangle.fill", text: reason, tint: Palette.warn.foreground)
        case .failed(let reason):
            return Appearance(
                symbol: "xmark.octagon.fill", text: "Processing failed: \(reason)", tint: Palette.danger.foreground)
        }
    }

    var body: some View {
        if let appearance {
            HStack(alignment: .top, spacing: NSPSpacing.medium) {
                Image(systemName: appearance.symbol).foregroundStyle(appearance.tint)
                Text(appearance.text).font(Typo.ui(13, .medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if status != .processing {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(NSPSpacing.medium)
            .background(Palette.surface, in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, NSPSpacing.large)
            .padding(.top, NSPSpacing.small)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// iPad only — creates a real, notes-capable meeting before recording
/// starts (docs/07 §5's pre-brief flow). `PadRootView` auto-selects it the
/// moment `session.meetingID` publishes, so no explicit navigation call is
/// needed here.
struct NewNoteButton: View {
    let session: RecordingSession

    var body: some View {
        Button {
            Task { await session.prepareDraft() }
        } label: {
            Label("New Note (before recording)", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// Shown on Today while a pre-recording draft exists — either a Meeting
/// pre-brief (docs/07 §5) or a standalone Note (`RecordingSession
/// .startStandaloneNote()`). Only the Meeting draft can promote into a
/// recording here — attaching a recording to an existing Note draft is
/// follow-up work (`startStandaloneNote()`'s own doc comment), so a Note
/// draft shows the saved-note state without a "Start Recording" control
/// that wouldn't do anything useful yet.
struct DraftingNotesCard: View {
    let session: RecordingSession
    let onSelectMeeting: ((MeetingID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            NSPStatusBadge(symbolName: "square.and.pencil", label: "Drafting Notes", tint: Palette.accent.foreground)
            if let meetingID = session.meetingID {
                Text("Notes are saved — start recording whenever you're ready.")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: NSPSpacing.medium) {
                    if let onSelectMeeting {
                        Button("Open Notes") { onSelectMeeting(meetingID) }
                            .buttonStyle(.bordered)
                    }
                    Button("Start Recording") { Task { await session.start() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Note saved.")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nspCard()
    }
}

/// Routes a meeting tap to either a navigation push (iPhone) or the
/// `onSelectMeeting` callback (iPad) — same routing `TodayView`'s own
/// `meetingLink` does for `needsReviewSection`. Not `private` — `DashboardView`
/// (a different file) reuses it for its own "Attention Required" section
/// rather than duplicating a third copy of the same routing logic.
@MainActor
@ViewBuilder
func dashboardMeetingLink<Label: View>(
    _ meetingID: MeetingID?, onSelectMeeting: ((MeetingID) -> Void)?, @ViewBuilder label: () -> Label
) -> some View {
    // A freestanding action/decision/insight has no meeting to link to —
    // the label just isn't tappable then.
    if let meetingID {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(meetingID)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: meetingID) { label() }
                .buttonStyle(.plain)
        }
    } else {
        label()
    }
}

/// The "Action Items" dashboard section — every open action across every
/// meeting, each still naming its source meeting and linking to it. Pulled
/// out of `TodayView` purely to stay under this repo's 250-line type-body
/// budget.
struct OpenActionsSection: View {
    let actions: [Action]
    let meetingTitles: [MeetingID: String]
    let now: Date
    let onSelectMeeting: ((MeetingID) -> Void)?
    let onSeeAll: () -> Void
    let onDelete: (ActionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            HStack {
                Text("Action Items").font(Typo.ui(17, .extrabold))
                Spacer()
                Button("See All", action: onSeeAll).font(Typo.ui(12.5, .medium))
            }
            ForEach(actions) { action in
                dashboardMeetingLink(action.meetingID, onSelectMeeting: onSelectMeeting) {
                    DashboardActionRow(
                        action: action,
                        meetingTitle: action.meetingID.flatMap { meetingTitles[$0] }
                            ?? (action.meetingID == nil ? "Personal" : "Untitled meeting"),
                        isOverdue: isOverdue(action), onDelete: { onDelete(action.actionID) })
                }
            }
        }
    }

    private func isOverdue(_ action: Action) -> Bool {
        switch action.date {
        case .explicit(let date), .inferred(let date): return date < now
        case .unresolved: return false
        }
    }
}

/// A cross-meeting action row for the dashboard — lighter than
/// `ActionRowCard` (no status-transition menu here; full management stays
/// in the Actions tab) since this view exists to answer "what's open and
/// where did it come from," not to manage every action inline.
struct DashboardActionRow: View {
    let action: Action
    let meetingTitle: String
    let isOverdue: Bool
    var onDelete: (() -> Void)?

    private var dueLabel: String? {
        switch action.date {
        case .explicit(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .inferred(let date): return "\(date.formatted(date: .abbreviated, time: .omitted)) (inferred)"
        case .unresolved: return nil
        }
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            NSPIconBadge(
                symbolName: action.status.symbolName, tint: isOverdue ? Palette.danger.foreground : action.status.tint)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(action.text).font(Typo.ui(14, .semibold)).lineLimit(2)
                HStack(spacing: NSPSpacing.extraSmall) {
                    Text(meetingTitle)
                    if let dueLabel {
                        Text("·")
                        Text(dueLabel)
                    }
                }
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(isOverdue ? Palette.danger.foreground : Palette.textTertiary)
            }

            Spacer(minLength: 0)

            if isOverdue {
                Text("Overdue")
                    .font(Typo.ui(10.5, .extrabold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, NSPSpacing.small)
                    .padding(.vertical, 4)
                    .background(Palette.danger.foreground, in: .capsule)
            }

            if let onDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .nspCard()
    }
}
