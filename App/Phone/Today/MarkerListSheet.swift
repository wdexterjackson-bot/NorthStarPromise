import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4: "dropping [a marker] immediately shows it in a dismissible
/// in-session list the user can rename with a short label right there, or
/// leave untitled and fill in later." Presented from `ActiveSessionCard`'s
/// marker count; every row is already a real `NoteBlock` (`RecordingSession
/// .addMarker`), so labeling here is the same edit `NotesTab` offers
/// post-hoc — just surfaced at the moment the user is most likely to
/// remember what the marker was for.
@MainActor
struct MarkerListSheet: View {
    let session: RecordingSession

    var body: some View {
        NavigationStack {
            Group {
                if session.markers.isEmpty {
                    ContentUnavailableView(
                        "No markers yet", systemImage: "flag",
                        description: Text("Tap Marker during the recording to drop one."))
                } else {
                    List {
                        ForEach(session.markers) { marker in
                            MarkerRow(session: session, marker: marker)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Markers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MarkerRow: View {
    let session: RecordingSession
    let marker: RecordingSession.SessionMarker

    @State private var text: String

    init(session: RecordingSession, marker: RecordingSession.SessionMarker) {
        self.session = session
        self.marker = marker
        if case .text(let existing) = marker.block.content {
            _text = State(initialValue: existing)
        } else {
            _text = State(initialValue: "")
        }
    }

    private var timeLabel: String {
        let totalSeconds = Int(marker.elapsedSecondsAtDrop)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        HStack(spacing: NSPSpacing.medium) {
            NSPIconBadge(symbolName: "flag.fill", tint: Palette.warn.foreground, size: 26)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                Text(timeLabel).font(Typo.ui(11.5, .bold)).foregroundStyle(Palette.textTertiary)
                TextField("What's this about?", text: $text)
                    .onSubmit { save() }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await session.deleteMarker(marker) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onDisappear { save() }
    }

    private func save() {
        guard text != currentText else { return }
        Task { await session.labelMarker(marker, text: text) }
    }

    private var currentText: String {
        if case .text(let existing) = marker.block.content { return existing }
        return ""
    }
}
