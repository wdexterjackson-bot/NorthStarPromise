import NSPDesignSystem
import SwiftUI

/// "The First Hour" wizard's shell — progress dots, Skip/Back/Next chrome,
/// and the assistant's own "speech bubble" framing per step
/// (`GettingStartedCoordinator.Step`). Presented full-screen regardless of
/// device (iPhone or iPad): a linear, one-question-at-a-time flow doesn't
/// fit the iPad's three-field Dashboard shell, same reasoning the old
/// Ambient Mode disclosure sheet used before it was removed.
struct GettingStartedWizardView: View {
    let environment: AppEnvironment
    /// Called once the wizard reaches a terminal state (finished or
    /// skipped) so the presenting view can dismiss the sheet.
    var onDone: () -> Void

    @State private var coordinator: GettingStartedCoordinator

    init(environment: AppEnvironment, onDone: @escaping () -> Void) {
        self.environment = environment
        self.onDone = onDone
        self._coordinator = State(initialValue: GettingStartedCoordinator(environment: environment))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.large) {
                        stepContent
                    }
                    .padding(NSPSpacing.large)
                }
                footer
            }
            .navigationTitle(coordinator.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip for now") {
                        Task {
                            await coordinator.skipEntirely()
                            onDone()
                        }
                    }
                }
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(GettingStartedCoordinator.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= coordinator.currentStep.rawValue ? Palette.accent.foreground : Palette.divider)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, NSPSpacing.large)
        .padding(.top, NSPSpacing.medium)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.currentStep {
        case .welcome: WizardWelcomeStep()
        case .identity: WizardIdentityStep(coordinator: coordinator)
        case .threads: WizardThreadsStep(coordinator: coordinator)
        case .people: WizardPeopleStep(coordinator: coordinator)
        case .calendar: WizardCalendarStep(coordinator: coordinator)
        case .recordingPrefs: WizardRecordingPrefsStep(environment: environment)
        case .ambient: WizardAmbientStep(environment: environment)
        case .sync: WizardSyncStep(environment: environment)
        case .review: WizardReviewStep(coordinator: coordinator)
        }
    }

    private var footer: some View {
        HStack {
            if coordinator.currentStep != .welcome {
                Button("Back") { coordinator.back() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(coordinator.currentStep == .review ? "Done" : "Continue") {
                Task {
                    if coordinator.currentStep == .review {
                        await coordinator.finish()
                        onDone()
                    } else {
                        await coordinator.advance()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(NSPSpacing.large)
        .background(Palette.canvas)
    }
}

struct WizardWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text("Let's get you set up").font(Typo.ui(22, .extrabold))
            Text(
                "I'm going to ask you a few things so I know how to be useful from day one — who matters, what "
                    + "you're juggling, and how you want me to record. About five minutes. Stop anytime — I'll "
                    + "pick up right where you left off, and everything here can be changed later in Settings, "
                    + "People, or Threads."
            )
            .font(Typo.ui(15, .medium))
            .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// A single "PA speech bubble" line — the shared look every step's
/// question uses (`GettingStartedWizardView`'s own doc comment).
struct WizardPromptBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.ui(16, .semibold))
            .italic()
            .foregroundStyle(Palette.textPrimary)
            .padding(NSPSpacing.medium)
            .background(Palette.accent.background, in: .rect(cornerRadius: 10))
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.accent.foreground).frame(width: 3)
            }
    }
}
