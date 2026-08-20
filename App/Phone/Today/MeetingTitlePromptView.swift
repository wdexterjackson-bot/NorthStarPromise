import NSPCore
import NSPDesignSystem
import SwiftUI

/// Shown once, right after Stop, only when the meeting is still carrying
/// the default `"Untitled meeting"` title (`RecordingSession.stop()`'s
/// `pendingTitleMeeting` gate) — a meeting already titled via the iPad
/// canvas's title band isn't redundantly prompted. Skipping leaves the
/// placeholder title in place; AI processing already started independently
/// in `stop()` and isn't gated on this either way.
struct MeetingTitlePromptView: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let onDone: (Meeting) -> Void

    @State private var title: String
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isTitleFocused: Bool

    init(meeting: Meeting, environment: AppEnvironment, onDone: @escaping (Meeting) -> Void) {
        self.meeting = meeting
        self.environment = environment
        self.onDone = onDone
        _title = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name this meeting") {
                    TextField("Meeting title", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(NSPColor.statusDanger)
                }
            }
            .navigationTitle("Recording saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onDone(meeting) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var updated = meeting
        updated.title = trimmed
        do {
            try await environment.meetingRepository.update(updated, at: environment.clock.now())
            onDone(updated)
        } catch {
            saveError = "\(error)"
        }
    }
}
