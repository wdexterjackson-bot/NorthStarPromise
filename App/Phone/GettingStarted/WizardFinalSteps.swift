import NSPCore
import NSPDesignSystem
import SwiftUI

/// Step 5 — a confirmation of the mandatory `docs/07 §12.3` processing-mode
/// choice, never a second ask. This step reads `Policy.defaultProcessingMode`/
/// `.announcementRequired`; it has no controls of its own, only a link to
/// Settings, so there is exactly one place in the app that question is
/// actually asked.
struct WizardRecordingPrefsStep: View {
    let environment: AppEnvironment

    private var modeDescription: String {
        switch environment.defaultPolicy?.defaultProcessingMode {
        case .localOnly: "nothing leaves this device"
        case .onDevicePreferred: "processed on this device when possible"
        case .cloudAllowed: "cloud processing allowed, per meeting"
        case nil: "not set yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Here's how I work: meetings are recorded by default unless you tell me otherwise — you'll "
                    + "always see and hear when I'm recording. Right now you've set me to \(modeDescription). "
                    + "Sound right?")
            Text("Change this anytime in Settings → Processing.")
                .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
        }
    }
}

/// Step 6 — a preview, not a decision the wizard forces. Mirrors Settings'
/// own Exercise Mode section exactly, including its 5-minute wheel picker.
struct WizardAmbientStep: View {
    let environment: AppEnvironment
    @State private var isEnabled = false
    @State private var durationMinutes = 60

    private static let durationOptions = Array(stride(from: 5, through: 150, by: 5))

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "I can also just listen for action items and reminders — no recording, no transcript kept "
                    + "— if you want a lighter-weight option for a run or a walk. Off by default; you can turn "
                    + "it on anytime in Settings.")
            Toggle("Exercise Mode", isOn: $isEnabled)
            if isEnabled {
                Picker("Session length", selection: $durationMinutes) {
                    ForEach(Self.durationOptions, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min").tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
            }
        }
        .task {
            isEnabled = environment.defaultPolicy?.ambientModeEnabled ?? false
            durationMinutes = environment.defaultPolicy?.ambientSessionDurationMinutes ?? 60
        }
        .onChange(of: isEnabled) { _, _ in save() }
        .onChange(of: durationMinutes) { _, _ in save() }
    }

    private func save() {
        guard var policy = environment.defaultPolicy else { return }
        policy.ambientModeEnabled = isEnabled
        policy.ambientSessionDurationMinutes = durationMinutes
        Task {
            try? await environment.policyRepository.update(policy, at: environment.clock.now())
            environment.refreshDefaultPolicy(policy)
        }
    }
}

/// Step 7 — mirrors the existing Settings sync toggle exactly.
struct WizardSyncStep: View {
    let environment: AppEnvironment
    @State private var isEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Want your meetings to show up on your other Apple devices too? That's your private "
                    + "iCloud — I'll never sync anything you've marked local-only.")
            Toggle("Sync to iCloud", isOn: $isEnabled)
        }
        .task { isEnabled = environment.defaultPolicy?.defaultProcessingMode != .localOnly }
        .onChange(of: isEnabled) { _, newValue in
            guard var policy = environment.defaultPolicy else { return }
            policy.defaultProcessingMode = newValue ? .onDevicePreferred : .localOnly
            Task {
                try? await environment.policyRepository.update(policy, at: environment.clock.now())
                environment.refreshDefaultPolicy(policy)
            }
        }
    }
}

/// Step 8 — the summary. Every row jumps straight to the real detail
/// screen it describes, so "change this later" is one tap, not a search.
struct WizardReviewStep: View {
    let coordinator: GettingStartedCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Here's what I've got: \(coordinator.createdThreads.count) thread"
                    + "\(coordinator.createdThreads.count == 1 ? "" : "s"), \(coordinator.createdPeople.count) "
                    + "\(coordinator.createdPeople.count == 1 ? "person" : "people"), "
                    + "\(coordinator.createdProjects.count) project"
                    + "\(coordinator.createdProjects.count == 1 ? "" : "s"). You can change any of this anytime "
                    + "— Settings, People, or Threads. Ready?")

            if coordinator.createdThreads.isEmpty && coordinator.createdPeople.isEmpty
                && coordinator.createdProjects.isEmpty
            {
                Text("Nothing added yet — that's fine, everything's still reachable from Settings anytime.")
                    .font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coordinator.createdThreads, id: \.threadID) { thread in
                        Label(thread.title, systemImage: "arrow.triangle.branch").font(Typo.ui(13.5, .semibold))
                    }
                    ForEach(coordinator.createdPeople, id: \.personID) { person in
                        Label(person.name, systemImage: "person.fill").font(Typo.ui(13.5, .semibold))
                    }
                    ForEach(coordinator.createdProjects, id: \.projectID) { project in
                        Label(project.name, systemImage: "folder.fill").font(Typo.ui(13.5, .semibold))
                    }
                }
            }

            if let saveError = coordinator.saveError {
                Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
            }
        }
    }
}
