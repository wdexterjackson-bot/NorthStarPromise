import NSPCore
import NSPDesignSystem
import SwiftUI

/// "Exercise Mode"'s home screen — the user-facing name for what's
/// internally still `AmbientCoordinator`/`AmbientSuggestion` etc.
/// ("Overheard" recommendation, 2026-08-22; relabeled 2026-08-22). Reached
/// from the capture button's long-press menu ("Record in Exercise Mode")
/// and My Work's toolbar. Start/Stop, live elapsed time, and the duration
/// reprompt — the same "tap to start, tap to stop" shape a meeting
/// recording already has, no separate consent step of its own. The
/// Ambient Suggestions inbox is a separate screen, reached from here once
/// there's something to review.
struct AmbientModeView: View {
    let environment: AppEnvironment

    @State private var coordinator: AmbientCoordinator

    init(environment: AppEnvironment) {
        self.environment = environment
        self._coordinator = State(initialValue: AmbientCoordinator(environment: environment))
    }

    private var isAmbientModeEnabled: Bool { environment.defaultPolicy?.ambientModeEnabled ?? false }
    private var durationMinutes: Int { environment.defaultPolicy?.ambientSessionDurationMinutes ?? 60 }

    var body: some View {
        NavigationStack {
            VStack(spacing: NSPSpacing.extraLarge) {
                Spacer(minLength: 0)
                statusCard
                controls
                Spacer(minLength: 0)
                NavigationLink("View Ambient Suggestions") {
                    AmbientSuggestionsInboxView(environment: environment)
                }
                .font(Typo.ui(13, .semibold))
            }
            .padding(NSPSpacing.large)
            .navigationTitle("Exercise Mode")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Continue Exercise Mode?", isPresented: continuePromptBinding, titleVisibility: .visible
            ) {
                Button("Continue") { coordinator.continueSession() }
                Button("Stop", role: .destructive) { coordinator.stop() }
            } message: {
                Text("This session's \(Self.durationLabel(durationMinutes)) is up.")
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch coordinator.state {
        case .idle:
            VStack(spacing: NSPSpacing.small) {
                Image(systemName: "ear").font(.system(size: 44)).foregroundStyle(Palette.textTertiary)
                Text("Exercise Mode is off").font(Typo.ui(15, .semibold))
                if !isAmbientModeEnabled {
                    Text("Turn it on in Settings → Exercise Mode before starting a session.")
                        .font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        case .listening, .awaitingContinuePrompt:
            VStack(spacing: NSPSpacing.small) {
                Image(systemName: "waveform").font(.system(size: 44)).foregroundStyle(Palette.accent.foreground)
                Text("Listening").font(Typo.ui(17, .extrabold))
                Text(Self.elapsedLabel(coordinator.elapsedSeconds))
                    .font(Typo.ui(13, .semibold)).monospacedDigit().foregroundStyle(Palette.textTertiary)
                Text("\(coordinator.suggestionsThisSession) caught so far")
                    .font(Typo.ui(12, .medium)).foregroundStyle(Palette.textQuaternary)
            }
        case .failed(let message):
            VStack(spacing: NSPSpacing.small) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36))
                    .foregroundStyle(Palette.danger.foreground)
                Text(message).font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch coordinator.state {
        case .idle, .failed:
            Button {
                Task { await coordinator.start(durationMinutes: durationMinutes) }
            } label: {
                Text("Start Exercise Mode").font(Typo.ui(15, .bold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isAmbientModeEnabled)
        case .listening:
            Button(role: .destructive) {
                coordinator.stop()
            } label: {
                Text("Stop").font(Typo.ui(15, .bold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .awaitingContinuePrompt:
            EmptyView()
        }
    }

    private var continuePromptBinding: Binding<Bool> {
        Binding(
            get: { coordinator.state == .awaitingContinuePrompt },
            set: { if !$0 { coordinator.stop() } })
    }

    private static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes) minutes" }
        if remainder == 0 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        return "\(hours) hour\(hours == 1 ? "" : "s") \(remainder) min"
    }
}
