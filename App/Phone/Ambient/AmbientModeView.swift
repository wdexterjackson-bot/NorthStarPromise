import NSPCore
import NSPDesignSystem
import SwiftUI

/// Ambient Mode's home screen ("Overheard" recommendation, 2026-08-22) —
/// reached from My Work's toolbar. Shows the one-time disclosure before
/// the feature can be used at all, then Start/Stop, live elapsed time, and
/// the duration reprompt. The Ambient Suggestions inbox is a separate
/// screen, reached from here once there's something to review.
struct AmbientModeView: View {
    let environment: AppEnvironment

    @State private var coordinator: AmbientCoordinator
    @State private var hasAcknowledgedDisclosure: Bool
    @State private var isShowingDisclosure = false

    private static let disclosureAcknowledgedKey = "com.dexterjackson.northstarpromise.ambientDisclosureAcknowledged"

    init(environment: AppEnvironment) {
        self.environment = environment
        self._coordinator = State(initialValue: AmbientCoordinator(environment: environment))
        self._hasAcknowledgedDisclosure = State(
            initialValue: UserDefaults.standard.bool(forKey: Self.disclosureAcknowledgedKey))
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
            .navigationTitle("Ambient Mode")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingDisclosure) {
                AmbientModeDisclosureView(
                    onAcknowledge: {
                        UserDefaults.standard.set(true, forKey: Self.disclosureAcknowledgedKey)
                        hasAcknowledgedDisclosure = true
                        isShowingDisclosure = false
                    })
            }
            .confirmationDialog(
                "Continue Ambient Mode?", isPresented: continuePromptBinding, titleVisibility: .visible
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
                Text("Ambient Mode is off").font(Typo.ui(15, .semibold))
                if !isAmbientModeEnabled {
                    Text("Turn it on in Settings → Ambient before starting a session.")
                        .font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        case .listening, .awaitingContinuePrompt:
            VStack(spacing: NSPSpacing.small) {
                Image(systemName: "waveform").font(.system(size: 44)).foregroundStyle(Palette.accent.foreground)
                Text("Recording in Process").font(Typo.ui(17, .extrabold))
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
                if !hasAcknowledgedDisclosure {
                    isShowingDisclosure = true
                } else {
                    Task { await coordinator.start(durationMinutes: durationMinutes) }
                }
            } label: {
                Text("Start Ambient Mode").font(Typo.ui(15, .bold)).frame(maxWidth: .infinity)
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
        minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60)\(minutes % 60 == 0 ? "" : ".5") hours"
    }
}

/// The one-time, hard-to-miss consent disclosure — must be acknowledged
/// before Ambient Mode can start for the first time ("Overheard," 2026-08-22).
private struct AmbientModeDisclosureView: View {
    let onAcknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NSPSpacing.large) {
                    Image(systemName: "ear.and.waveform").font(.system(size: 40))
                        .foregroundStyle(Palette.accent.foreground)
                    Text("Before you turn this on").font(Typo.display(24))
                    Group {
                        disclosureRow(
                            "\"Recording in Process\" plays out loud",
                            "Every time a session starts or renews, anyone in the room hears it — not just you.")
                        disclosureRow(
                            "Nothing is recorded",
                            "No audio file, no saved transcript. A short text excerpt is kept only for the "
                                + "specific moments you later choose to accept as an action or decision.")
                        disclosureRow(
                            "You review everything",
                            "Nothing is added to your workspace automatically. Every catch waits in the Ambient "
                                + "Suggestions inbox until you accept or dismiss it.")
                        disclosureRow(
                            "You're responsible for who's in the room",
                            "Recording or processing someone else's conversation without their knowledge may be "
                                + "restricted by law where you are. Use Ambient Mode somewhere everyone present "
                                + "understands what \"Recording in Process\" means.")
                    }
                    Button("I Understand — Enable Ambient Mode") {
                        onAcknowledge()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(NSPSpacing.large)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func disclosureRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typo.ui(14.5, .bold))
            Text(body).font(Typo.ui(13, .medium)).foregroundStyle(Palette.textTertiary)
        }
    }
}
