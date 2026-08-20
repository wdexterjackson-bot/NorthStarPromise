import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Library row shape, reused by Today's "Needs review"
/// section too: title (or "Untitled meeting" when sensitive/absent), date,
/// duration, and a state badge. Action count isn't shown yet — NSPActions
/// isn't wired into any screen in this pass, and a fake "0" would be worse
/// than omitting the field entirely (docs/07 §11).
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
            NSPIconBadge(symbolName: captureIcon, tint: MeetingStateBadge.appearance(for: meeting.lifecycleState).tint)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                HStack(spacing: NSPSpacing.small) {
                    Text(meeting.startedAt, style: .date)
                    if let durationLabel {
                        Text("·")
                        Text(durationLabel)
                    }
                }
                .font(.caption)
                .foregroundStyle(NSPColor.secondaryText)

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
                        .foregroundStyle(NSPColor.secondaryText)
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

/// Maps `MeetingState` (docs/02 §3) to a symbol/label/tint — presentation
/// logic that belongs at the call site, not inside `NSPDesignSystem`
/// (`NSPStatusBadge`'s own doc comment explains why).
struct MeetingStateBadge: View {
    let state: MeetingState

    var body: some View {
        let appearance = Self.appearance(for: state)
        NSPStatusBadge(symbolName: appearance.symbol, label: appearance.label, tint: appearance.tint)
    }

    /// A named type in place of a 3-member tuple (SwiftLint's `large_tuple`
    /// rule caps tuples at 2).
    fileprivate struct Appearance {
        let symbol: String
        let label: String
        let tint: Color
    }

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate static func appearance(for state: MeetingState) -> Appearance {
        switch state {
        case .ready: return Appearance(symbol: "circle", label: "Ready", tint: NSPColor.statusNeutral)
        case .arming: return Appearance(symbol: "hourglass", label: "Preparing", tint: NSPColor.statusInProgress)
        case .recording:
            return Appearance(symbol: "record.circle.fill", label: "Recording", tint: NSPColor.statusDanger)
        case .paused: return Appearance(symbol: "pause.circle.fill", label: "Paused", tint: NSPColor.statusWarning)
        case .interrupted:
            return Appearance(
                symbol: "exclamationmark.triangle.fill", label: "Interrupted", tint: NSPColor.statusWarning)
        case .finalizing:
            return Appearance(symbol: "hourglass", label: "Finishing up", tint: NSPColor.statusInProgress)
        case .processing:
            return Appearance(symbol: "gearshape.fill", label: "Processing", tint: NSPColor.statusInProgress)
        case .readyForReview:
            return Appearance(symbol: "checkmark.circle.fill", label: "Needs review", tint: NSPColor.statusWarning)
        case .approved:
            return Appearance(symbol: "checkmark.seal.fill", label: "Approved", tint: NSPColor.statusSuccess)
        case .edited: return Appearance(symbol: "pencil.circle.fill", label: "Edited", tint: NSPColor.statusNeutral)
        case .shared: return Appearance(symbol: "paperplane.fill", label: "Shared", tint: NSPColor.statusSuccess)
        case .archived:
            return Appearance(symbol: "archivebox.fill", label: "Archived", tint: NSPColor.statusNeutral)
        case .deleted: return Appearance(symbol: "trash.fill", label: "Deleted", tint: NSPColor.statusDanger)
        case .restored:
            return Appearance(
                symbol: "arrow.uturn.backward.circle.fill", label: "Restored", tint: NSPColor.statusNeutral)
        case .purged: return Appearance(symbol: "trash.slash.fill", label: "Purged", tint: NSPColor.statusDanger)
        case .recoverable:
            return Appearance(
                symbol: "exclamationmark.triangle.fill", label: "Recoverable", tint: NSPColor.statusWarning)
        case .savedRaw: return Appearance(symbol: "checkmark.circle", label: "Saved", tint: NSPColor.statusSuccess)
        case .partialFailure:
            return Appearance(
                symbol: "exclamationmark.triangle.fill", label: "Partial failure", tint: NSPColor.statusDanger)
        case .failed: return Appearance(symbol: "xmark.circle.fill", label: "Failed", tint: NSPColor.statusDanger)
        }
    }
}
