import NSPCore
import NSPDesignSystem
import SwiftUI

/// A standalone Note's own detail screen — metadata, an editable title, and
/// delete. No text/ink editing surface yet: nothing writes a `NoteBlock`
/// against `.note` ownership today (`RecordingSession.startStandaloneNote()`'s
/// own doc comment — this pass only covers creating the row itself), so
/// there's no content here to show beyond what the row already displays.
@MainActor
struct NoteDetailView: View {
    let noteID: NoteID
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var note: Note?
    @State private var title = ""
    @State private var loadError: String?
    @State private var isConfirmingDelete = false

    private var durationLabel: String? {
        guard let note, note.canonicalDuration.sampleCount > 0 else { return nil }
        let totalSeconds = Int(note.canonicalDuration.seconds)
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let note {
                List {
                    Section {
                        TextField("Title", text: $title)
                            .onSubmit { Task { await saveTitle() } }
                    }
                    Section {
                        LabeledContent("Created", value: note.startedAt.formatted(date: .abbreviated, time: .shortened))
                        if let durationLabel {
                            LabeledContent("Recording", value: durationLabel)
                        }
                        LabeledContent("Status") { MeetingStateBadge(state: note.lifecycleState) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(note == nil)
            }
        }
        .confirmationDialog(
            "Delete this note?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the note. Can't be undone.")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            note = try await environment.noteRepository.find(noteID)
            title = note?.title ?? ""
        } catch {
            loadError = "\(error)"
        }
    }

    private func saveTitle() async {
        guard var note else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != note.title else { return }
        note.title = trimmed
        do {
            try await environment.noteRepository.update(note, at: environment.clock.now())
            self.note = note
        } catch {
            loadError = "\(error)"
        }
    }

    private func delete() async {
        do {
            try await environment.deleteNote(noteID)
            dismiss()
        } catch {
            loadError = "\(error)"
        }
    }
}
