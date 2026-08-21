import NSPCore
import NSPDesignSystem
import SwiftUI

/// Dashboard's "Attention Required" section — what needs a decision across
/// everything, not just today. Pulled out of `DashboardView` purely to keep
/// that type under this repo's 250-line type-body budget.
struct DashboardAttentionSection: View {
    let meetings: [Meeting]
    let onSelectMeeting: ((MeetingID) -> Void)?
    let onDelete: (MeetingID) -> Void

    var body: some View {
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Attention Required").font(Typo.ui(17, .extrabold))
                ForEach(meetings) { meeting in
                    dashboardMeetingLink(meeting.meetingID, onSelectMeeting: onSelectMeeting) {
                        MeetingRow(meeting: meeting, onDelete: { onDelete(meeting.meetingID) })
                            .nspCard()
                    }
                }
            }
        }
    }
}

/// A compact "go to this area" card — icon, title, subtitle, chevron —
/// used by the Dashboard's remaining single-tab entry point (People) so it
/// doesn't hand-roll its own button chrome.
struct DashboardEntryCard: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NSPSpacing.medium) {
                Image(systemName: symbolName).font(Typo.ui(17, .bold)).foregroundStyle(Palette.accent.foreground)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.ui(12.5, .bold))
                    Text(subtitle).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        }
        .buttonStyle(.plain)
    }
}

/// Dashboard's "Projects" section body — real data via `ProjectRepository`,
/// an honest empty state when none exist yet (docs/07 §11). Same
/// extraction reason as `DashboardAttentionSection` above.
struct DashboardProjectsSection: View {
    let projects: [Project]
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            HStack {
                Text("Projects").font(Typo.ui(17, .extrabold))
                Spacer()
                Button("See All", action: onSeeAll).font(Typo.ui(12.5, .medium))
            }
            if projects.isEmpty {
                ContentUnavailableView(
                    "Group meetings into projects", systemImage: "folder.badge.plus",
                    description: Text(
                        "Create a project from the Projects tab to organize meetings and notes by initiative."))
            } else {
                ForEach(projects) { project in
                    Button(action: onSeeAll) {
                        HStack(spacing: NSPSpacing.medium) {
                            NSPIconBadge(symbolName: "folder.fill", tint: Palette.accent.foreground)
                            Text(project.name).font(Typo.ui(14, .semibold)).foregroundStyle(Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(Typo.ui(11.5, .medium)).foregroundStyle(
                                Palette.textTertiary)
                        }
                        .nspCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
