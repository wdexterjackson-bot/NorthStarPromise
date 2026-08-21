import NSPCore
import NSPDesignSystem
import SwiftUI

/// A Brain Dump's own detail screen — deliberately minimal: metadata and
/// delete, nothing else yet. There's no transcript/notes UI here because
/// nothing writes one for a Brain Dump today (`RecordingSessionBrainDumpAndNote
/// .swift`'s own doc comments: no AI processing, no note-taking surface
/// wired to `.brainDump` ownership) — building a playback/notes experience
/// this pass would be UI for data that can't exist yet, not a real feature.
/// `NSP-154` (artifact distribution) is the ticket that gives a Brain Dump
/// real content to show here.
@MainActor
struct BrainDumpDetailView: View {
    let brainDumpID: BrainDumpID
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var brainDump: BrainDump?
    @State private var loadError: String?
    @State private var isConfirmingDelete = false

    private var durationLabel: String? {
        guard let brainDump, brainDump.canonicalDuration.sampleCount > 0 else { return nil }
        let totalSeconds = Int(brainDump.canonicalDuration.seconds)
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let brainDump {
                List {
                    Section {
                        LabeledContent(
                            "Recorded", value: brainDump.startedAt.formatted(date: .abbreviated, time: .shortened))
                        if let durationLabel {
                            LabeledContent("Duration", value: durationLabel)
                        }
                        LabeledContent("Status") { MeetingStateBadge(state: brainDump.lifecycleState) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Brain Dump")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(brainDump == nil)
            }
        }
        .confirmationDialog(
            "Delete this Brain Dump?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the recording. Can't be undone.")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            brainDump = try await environment.brainDumpRepository.find(brainDumpID)
        } catch {
            loadError = "\(error)"
        }
    }

    private func delete() async {
        do {
            try await environment.deleteBrainDump(brainDumpID)
            dismiss()
        } catch {
            loadError = "\(error)"
        }
    }
}
