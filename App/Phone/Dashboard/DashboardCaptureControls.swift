import NSPDesignSystem
import SwiftUI

/// The floating capture control (§5.8) — tap starts the most common
/// action immediately; long-press offers the app's recording intents.
/// Demoted to a persistent control rather than the screen's hero, per the
/// spec's whole premise (§0): "recording is table stakes, memory is the
/// product." Split into its own file alongside `DashboardNotesOnlyButton`/
/// `DashboardBrainDumpButton` once `DashboardSections.swift` hit this
/// repo's 400-line file budget.
///
/// Three distinct kinds of thing this app can start, none of them the
/// same as another: a **meeting with a recording** (this button); a
/// **meeting without a recording** (`DashboardNotesOnlyButton` —
/// `RecordingSession.prepareDraft()`'s `.draft` state, notes-capable, no
/// audio ever starts unless the user later promotes it); and a
/// **Brain Dump / Mental Note** (`DashboardBrainDumpButton` — audio *does*
/// record, but it isn't a meeting: not tied to one project, and its
/// generated artifacts are meant to be distributed across whichever
/// meetings/projects/action items they turn out to be relevant to, rather
/// than living under one meeting the way a recorded meeting's output
/// does — that distribution step isn't built yet, see `docs/09-BACKLOG.md`).
struct DashboardCaptureButton: View {
    let isRecording: Bool
    let onStartMeeting: () -> Void
    let onStartMentalNote: () -> Void
    let onImportAudio: () -> Void

    var body: some View {
        Menu {
            Button("Record a Meeting", systemImage: "mic.fill", action: onStartMeeting)
            Button("Record a Mental Note", systemImage: "brain.head.profile", action: onStartMentalNote)
            Button("Import Recording", systemImage: "square.and.arrow.down", action: onImportAudio)
        } label: {
            ZStack {
                Circle().fill(Palette.canvas).frame(width: 68, height: 68)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.record, Palette.recordDark], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 58, height: 58)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.record.opacity(0.34), radius: 10, x: 0, y: 10)
        } primaryAction: {
            onStartMeeting()
        }
        .accessibilityLabel(isRecording ? "Recording in progress" : "Start capture")
    }
}

/// A dedicated, always-visible companion to `DashboardCaptureButton` for
/// starting a **meeting without a recording** — notes only, audio never
/// starts — in a single tap. `Palette.accent`'s blue, matching the app's
/// existing "interactive, non-destructive" convention rather than either
/// of the two record-adjacent colors either side of it. iPad-only today
/// (the sidebar has the width for three controls side by side; iPhone's
/// floating single button stays the entry point there via its long-press
/// menu).
struct DashboardNotesOnlyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.canvas).frame(width: 52, height: 52)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent.foreground, Palette.accent.foreground.opacity(0.78)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.accent.foreground.opacity(0.3), radius: 8, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start notes")
        .accessibilityHint("Takes notes without recording audio")
    }
}

/// A dedicated companion for **Brain Dump / Mental Note** — a real audio
/// recording (`RecordingSession.startBrainDump()`), just not a meeting: not tied
/// to one project, and (once the distribution step exists) its output
/// gets split across whatever meetings/projects/actions it's actually
/// relevant to instead of staying under one standalone record. Its own
/// reserved color (`Palette.brainDump`) — not `accent`'s blue, not
/// `record`'s red — so it reads as neither "an ordinary interactive
/// control" nor "a meeting recording."
struct DashboardBrainDumpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.canvas).frame(width: 52, height: 52)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.brainDump, Palette.brainDump.opacity(0.78)], startPoint: .top,
                            endPoint: .bottom)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.brainDump.opacity(0.3), radius: 8, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a brain dump")
        .accessibilityHint("Records audio, not tied to a meeting or a single project")
    }
}
