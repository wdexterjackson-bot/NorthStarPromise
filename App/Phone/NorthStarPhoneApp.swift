import AVFAudio
import NSPCore
import SwiftUI
import UserNotifications

@main
struct NorthStarPhoneApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: NorthStarAppDelegate
    @State private var environment: AppEnvironment?
    @State private var launchError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let environment {
                    RootView(environment: environment)
                } else if let launchError {
                    ContentUnavailableView(
                        "Couldn't start", systemImage: "exclamationmark.triangle",
                        description: Text(launchError))
                } else {
                    ProgressView()
                }
            }
            .task {
                guard environment == nil else { return }
                do {
                    let newEnvironment = try AppEnvironment()
                    // `bootstrap()` (and, in DEBUG, fixture seeding) must
                    // finish before `RootView` mounts — every screen's
                    // `.task` runs exactly once per view identity, so a
                    // screen that raced ahead of `defaultPolicy`/
                    // `selfPersonID` existing would bail out early and
                    // never retry, permanently missing data that arrives a
                    // moment later.
                    try await newEnvironment.bootstrap()
                    #if DEBUG
                        await DebugFixtures.seedIfNeeded(environment: newEnvironment)
                    #endif
                    environment = newEnvironment
                    appDelegate.attach(newEnvironment.scheduledRecordingCoordinator)
                    if let workspaceID = newEnvironment.defaultPolicy?.workspaceID {
                        Task { await newEnvironment.syncCoordinator.syncNow(workspaceID: workspaceID) }
                        if newEnvironment.featureFlagProvider.isEnabled(.scheduledRecording) {
                            ScheduledRecordingNotificationScheduler.registerCategory()
                            Task {
                                await newEnvironment.scheduledRecordingCoordinator.reconcile(workspaceID: workspaceID)
                            }
                        }
                        Task {
                            await Self.requestLaunchPermissionsIfNeeded(
                                environment: newEnvironment, workspaceID: workspaceID)
                        }
                    }
                } catch {
                    launchError = "\(error)"
                }
            }
        }
        // Pulls whatever another device pushed while this one was in the
        // background — best-effort, same non-blocking shape as the
        // launch-time and post-Stop sync calls.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let environment, let workspaceID = environment.defaultPolicy?.workspaceID else {
                return
            }
            Task { await environment.syncCoordinator.syncNow(workspaceID: workspaceID) }
        }
    }

    private static let openActionStatuses: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]

    /// Asks for microphone access unconditionally — every recording needs
    /// it, and asking here means the first "Start Recording" tap never
    /// stalls on a system prompt — and for notification access only when
    /// the user already has something a notification would serve: a
    /// pending scheduled recording, or an open action item. A brand-new
    /// workspace with neither isn't asked for a permission with nothing
    /// behind it yet. Both checks read `.undetermined`/`.notDetermined`
    /// first, so a previously denied permission is never re-prompted
    /// (iOS wouldn't show a system dialog for it anyway — only Settings
    /// can change that). Runs once, inside the launch `.task`'s one-time
    /// body, so neither can re-prompt again until the app relaunches.
    private static func requestLaunchPermissionsIfNeeded(environment: AppEnvironment, workspaceID: WorkspaceID) async {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }

        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        guard notificationSettings.authorizationStatus == .notDetermined else { return }

        let hasPendingSchedule =
            !((try? await environment.scheduledRecordingRepository.fetchPending(
                workspaceID: workspaceID)) ?? []).isEmpty
        let hasOpenAction =
            (try? await environment.actionRepository.fetchAll(workspaceID: workspaceID))?
            .contains { Self.openActionStatuses.contains($0.status) } ?? false

        guard hasPendingSchedule || hasOpenAction else { return }
        _ = await ScheduledRecordingNotificationScheduler().requestAuthorization()
    }
}
