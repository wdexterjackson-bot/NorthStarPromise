import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Library row shape, reused by Today's "Needs review"
/// section too: title (or "Untitled meeting" when sensitive/absent), date,
/// duration, and a state badge. Action count isn't shown yet — NSPActions
/// isn't wired into any screen in this pass, and a fake "0" would be worse
/// than omitting the field entirely (docs/07 §11). Migrated onto the
/// Dashboard redesign's `Palette`/`Typo` — this row appears everywhere a
/// meeting does, so it's the highest-leverage single file for the
/// "consistent throughout the app" migration (Dashboard scope plan).
@MainActor
struct MeetingRow: View {
    let meeting: Meeting
    /// `nil` renders no delete affordance at all — every call site wires
    /// this today, but a future read-only context (e.g. a shared meeting
    /// the viewer doesn't own) can omit it without a separate row type.
    var onDelete: (() -> Void)?

    @State private var isConfirmingDelete = false

    private var displayTitle: String {
        if meeting.isTitleSensitive || meeting.title.isEmpty {
            return "Untitled meeting"
        }
        return meeting.title
    }

    private var durationLabel: String? {
        guard meeting.canonicalDuration.sampleCount > 0 else { return nil }
        let totalSeconds = Int(meeting.canonicalDuration.seconds)
        if totalSeconds >= 3600 {
            return String(format: "%dh %02dm", totalSeconds / 3600, (totalSeconds % 3600) / 60)
        }
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    private var captureIcon: String {
        switch meeting.captureMode {
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .pad: return "ipad"
        case .import: return "square.and.arrow.down"
        case .onlineAssistant: return "video.fill"
        case .dialer: return "phone.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: NSPSpacing.medium) {
            TintedIconTile(
                symbolName: captureIcon, tint: MeetingStateBadge.appearance(for: meeting.lifecycleState).tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle).font(Typo.ui(14, .bold)).foregroundStyle(Palette.textPrimary)
                HStack(spacing: NSPSpacing.small) {
                    Text(meeting.startedAt, style: .date)
                    if let durationLabel {
                        Text("·")
                        Text(durationLabel)
                    }
                }
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)

                MeetingStateBadge(state: meeting.lifecycleState)
            }

            Spacer(minLength: 0)

            if let onDelete {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete this meeting?", isPresented: $isConfirmingDelete, titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes the recording, notes, transcript, and any linked action items. Can't be undone.")
                }
            }
        }
    }
}

/// Maps `MeetingState` (docs/02 §3) to a `StatusChip` style/label —
/// presentation logic that belongs at the call site, not inside
/// `NSPDesignSystem` (`StatusChip`'s own doc comment explains why).
struct MeetingStateBadge: View {
    let state: MeetingState

    var body: some View {
        let appearance = Self.appearance(for: state)
        StatusChip(appearance.label, style: appearance.style)
    }

    /// A named type in place of a 3-member tuple (SwiftLint's `large_tuple`
    /// rule caps tuples at 2). `tint` is the `TintedIconTile` color the
    /// capture-mode icon uses; `style`/`label` drive the `StatusChip`.
    fileprivate struct Appearance {
        let label: String
        let style: StatusChip.Style
        let tint: SemanticTint
    }

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate static func appearance(for state: MeetingState) -> Appearance {
        switch state {
        case .ready: return Appearance(label: "Ready", style: .neutral, tint: neutralTint)
        case .arming: return Appearance(label: "Preparing", style: .neutral, tint: Palette.accent)
        case .recording: return Appearance(label: "Recording", style: .danger, tint: Palette.danger)
        case .paused: return Appearance(label: "Paused", style: .warn, tint: Palette.warn)
        case .interrupted: return Appearance(label: "Interrupted", style: .warn, tint: Palette.warn)
        case .finalizing: return Appearance(label: "Finishing up", style: .neutral, tint: Palette.accent)
        case .processing: return Appearance(label: "Processing", style: .neutral, tint: Palette.accent)
        case .readyForReview: return Appearance(label: "Needs review", style: .warn, tint: Palette.warn)
        case .approved: return Appearance(label: "Approved", style: .success, tint: Palette.success)
        case .edited: return Appearance(label: "Edited", style: .neutral, tint: neutralTint)
        case .shared: return Appearance(label: "Shared", style: .success, tint: Palette.success)
        case .archived: return Appearance(label: "Archived", style: .neutral, tint: neutralTint)
        case .deleted: return Appearance(label: "Deleted", style: .danger, tint: Palette.danger)
        case .restored: return Appearance(label: "Restored", style: .neutral, tint: neutralTint)
        case .purged: return Appearance(label: "Purged", style: .danger, tint: Palette.danger)
        case .recoverable: return Appearance(label: "Recoverable", style: .warn, tint: Palette.warn)
        case .savedRaw: return Appearance(label: "Saved", style: .success, tint: Palette.success)
        case .partialFailure:
            // Warning, not danger — matching `.interrupted`/`.recoverable`'s
            // tint. This state is reached whenever *some* processing step
            // didn't produce output (most commonly: the on-device AI
            // summarizer isn't available on this device/OS, docs/06 §6's
            // capability-detected note), while the transcript itself is
            // often still there and readable — that's a legitimate, honest
            // outcome (`IntelligenceCoordinator`'s own doc comment), not the
            // same severity as a real failure, so it shouldn't read as one.
            return Appearance(label: "Needs attention", style: .warn, tint: Palette.warn)
        case .failed: return Appearance(label: "Failed", style: .danger, tint: Palette.danger)
        }
    }

    private static let neutralTint = SemanticTint(
        foreground: Palette.textSecondary, background: Palette.fill, border: Palette.border)
}
