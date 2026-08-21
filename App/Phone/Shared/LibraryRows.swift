import NSPCore
import NSPDesignSystem
import SwiftUI

/// `BrainDumpRow`/`NoteRow` — `MeetingRow`'s exact visual shape (icon tile,
/// title, date/duration line, lifecycle badge, delete menu), for the other
/// two containers the Library now lists alongside meetings
/// (docs/09-BACKLOG.md, "rescoping the meeting-organization data model": a
/// Brain Dump and a Note are never disguised meetings, so Library must show
/// them as their own kinds, not imply everything in it is a `Meeting`).
/// Kept as separate types rather than parameterizing `MeetingRow` — the
/// three have different fields (no capture-mode icon or title for a Brain
/// Dump; no capture-mode icon for a Note) and forcing one generic row to
/// paper over that would be the premature abstraction.
@MainActor
struct BrainDumpRow: View {
    let brainDump: BrainDump
    var onDelete: (() -> Void)?

    @State private var isConfirmingDelete = false

    private var durationLabel: String? {
        guard brainDump.canonicalDuration.sampleCount > 0 else { return nil }
        let totalSeconds = Int(brainDump.canonicalDuration.seconds)
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: NSPSpacing.medium) {
            TintedIconTile(symbolName: "brain.head.profile", tint: Palette.brainDumpTint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Brain Dump").font(Typo.ui(14, .bold)).foregroundStyle(Palette.textPrimary)
                HStack(spacing: NSPSpacing.small) {
                    Text(brainDump.startedAt, style: .date)
                    if let durationLabel {
                        Text("·")
                        Text(durationLabel)
                    }
                }
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)

                MeetingStateBadge(state: brainDump.lifecycleState)
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
                    "Delete this Brain Dump?", isPresented: $isConfirmingDelete, titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes the recording. Can't be undone.")
                }
            }
        }
    }
}

@MainActor
struct NoteRow: View {
    let note: Note
    var onDelete: (() -> Void)?

    @State private var isConfirmingDelete = false

    private var displayTitle: String { note.title.isEmpty ? "Untitled note" : note.title }

    private var durationLabel: String? {
        guard note.canonicalDuration.sampleCount > 0 else { return nil }
        let totalSeconds = Int(note.canonicalDuration.seconds)
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        HStack(alignment: .top, spacing: NSPSpacing.medium) {
            TintedIconTile(symbolName: "pencil.and.list.clipboard", tint: Palette.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle).font(Typo.ui(14, .bold)).foregroundStyle(Palette.textPrimary)
                HStack(spacing: NSPSpacing.small) {
                    Text(note.startedAt, style: .date)
                    if let durationLabel {
                        Text("·")
                        Text(durationLabel)
                    }
                }
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Palette.textTertiary)

                MeetingStateBadge(state: note.lifecycleState)
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
                    "Delete this note?", isPresented: $isConfirmingDelete, titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes the note. Can't be undone.")
                }
            }
        }
    }
}
