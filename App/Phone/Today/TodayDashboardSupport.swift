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
                    onDone: { updated in
                        session.dismissTitlePrompt(meeting: updated)
                        Task { await onDismiss() }
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

/// Shown on Today while a pre-recording draft meeting exists (docs/07 §5)
/// — notes are already being saved; recording can start whenever the user
/// is ready.
struct DraftingNotesCard: View {
    let session: RecordingSession
    let onSelectMeeting: ((MeetingID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            NSPStatusBadge(symbolName: "square.and.pencil", label: "Drafting Notes", tint: NSPColor.accent)
            Text("Notes are saved — start recording whenever you're ready.")
                .font(.callout)
                .foregroundStyle(NSPColor.secondaryText)
            HStack(spacing: NSPSpacing.medium) {
                if let onSelectMeeting, let meetingID = session.meetingID {
                    Button("Open Notes") { onSelectMeeting(meetingID) }
                        .buttonStyle(.bordered)
                }
                Button("Start Recording") { Task { await session.start() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nspCard()
    }
}

/// A compact glanceable stat — "N meetings this week," "N open actions."
struct DashboardStatChip: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(NSPColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NSPSpacing.medium)
        .background(NSPColor.cardBackground, in: .rect(cornerRadius: 12, style: .continuous))
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
                symbolName: action.status.symbolName, tint: isOverdue ? NSPColor.statusDanger : action.status.tint)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(action.text).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: NSPSpacing.extraSmall) {
                    Text(meetingTitle)
                    if let dueLabel {
                        Text("·")
                        Text(dueLabel)
                    }
                }
                .font(.caption)
                .foregroundStyle(isOverdue ? NSPColor.statusDanger : NSPColor.secondaryText)
            }

            Spacer(minLength: 0)

            if isOverdue {
                Text("Overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, NSPSpacing.small)
                    .padding(.vertical, 4)
                    .background(NSPColor.statusDanger, in: .capsule)
            }

            if let onDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(NSPColor.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .nspCard()
    }
}
