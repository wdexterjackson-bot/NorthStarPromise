import NSPCore
import NSPDesignSystem
import SwiftUI

/// The "Upcoming" section body shared by `DashboardView` (every upcoming
/// schedule, any date) and `TodayView` (today's only) — docs/07 §4/§2.1.
/// Pulled into its own file purely to stay under this repo's 400-line
/// file-length budget.
struct UpcomingRecordingsSection: View {
    let items: [ScheduledRecording]
    let onScheduleTapped: () -> Void
    var onEdit: ((ScheduledRecording) -> Void)?
    var onCancel: ((ScheduledRecording) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            HStack {
                Text("Upcoming").font(Typo.ui(17, .extrabold))
                Spacer()
                Button("Schedule", action: onScheduleTapped).font(Typo.ui(12.5, .medium))
            }
            if items.isEmpty {
                Text("Schedule a recording to start and stop it automatically at set times.")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(items) { item in
                    UpcomingRecordingRow(
                        item: item, onEdit: onEdit.map { edit in { edit(item) } },
                        onCancel: onCancel.map { cancel in { cancel(item) } })
                }
            }
        }
    }
}

/// One pending Scheduled Recording (docs/07 §2.1) — title, start time, and
/// its notification alert style, so the user can tell at a glance whether
/// it'll ring, vibrate, or arrive silently. `onEdit`/`onCancel` are `nil` in
/// any context that shouldn't offer them (none today — both `TodayView` and
/// `DashboardView` always wire both).
struct UpcomingRecordingRow: View {
    let item: ScheduledRecording
    var onEdit: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var isConfirmingCancel = false

    private var alertSymbol: String {
        switch item.alertStyle {
        case .sound: return "bell.fill"
        case .vibrateOnly: return "iphone.radiowaves.left.and.right"
        case .silent: return "bell.slash.fill"
        }
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            NSPIconBadge(symbolName: "calendar.badge.clock", tint: Palette.accent.foreground)
            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(item.title).font(Typo.ui(14, .bold))
                HStack(spacing: NSPSpacing.extraSmall) {
                    Text(item.scheduledStart, style: .date)
                    Text(item.scheduledStart, style: .time)
                }
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: alertSymbol).foregroundStyle(Palette.textTertiary)
            if onEdit != nil || onCancel != nil {
                Menu {
                    if let onEdit {
                        Button("Edit", systemImage: "pencil", action: onEdit)
                    }
                    if onCancel != nil {
                        Button("Cancel Recording", systemImage: "xmark.circle", role: .destructive) {
                            isConfirmingCancel = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Cancel this scheduled recording?", isPresented: $isConfirmingCancel, titleVisibility: .visible
                ) {
                    Button("Cancel Recording", role: .destructive) { onCancel?() }
                    Button("Keep It", role: .cancel) {}
                }
            }
        }
        .nspCard()
    }
}
