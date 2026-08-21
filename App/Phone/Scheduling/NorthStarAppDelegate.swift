import Foundation
import NSPCore
import UIKit
import UserNotifications

/// This app's first `AppDelegate` — needed only because
/// `UNUserNotificationCenter`'s delegate must be assigned before the system
/// might deliver a queued notification response, and `AppEnvironment` is
/// constructed asynchronously after the process is already running
/// (`NorthStarPhoneApp.swift`'s `.task`). Kept as thin as the rest of
/// `App/Phone` (`CLAUDE.md` §3) — routing only, everything real happens in
/// `ScheduledRecordingCoordinator`.
@MainActor
final class NorthStarAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// `nil` during the cold-launch window before `NorthStarPhoneApp`'s
    /// `.task` finishes constructing `AppEnvironment`. An action arriving
    /// while this is `nil` is queued in `pendingAction`, never dropped.
    private var coordinator: ScheduledRecordingCoordinator?
    private var pendingAction: (actionIdentifier: String, scheduledRecordingID: ScheduledRecordingID)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called once `AppEnvironment`/its coordinator exist — flushes an
    /// action that arrived before this point rather than losing it.
    func attach(_ coordinator: ScheduledRecordingCoordinator) {
        self.coordinator = coordinator
        if let pendingAction {
            self.pendingAction = nil
            route(
                actionIdentifier: pendingAction.actionIdentifier,
                scheduledRecordingID: pendingAction.scheduledRecordingID, into: coordinator)
        }
    }

    /// `nonisolated` (and hops to `@MainActor` internally via `Task`) —
    /// `UNUserNotificationCenterDelegate`'s requirements aren't themselves
    /// actor-isolated, and neither `UNNotificationResponse` nor its
    /// `userInfo` dictionary is `Sendable`, so the conformance itself has
    /// to stay non-isolated even though this class's own state is
    /// `@MainActor`. Only the plain `String` actually needed is pulled out
    /// here, before hopping — `completionHandler` is called immediately
    /// rather than deferred into the `Task`, since `UNUserNotificationCenter`
    /// only needs to know the response was received, not that routing into
    /// the coordinator has finished.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let scheduledRecordingIDString =
            response.notification.request.content.userInfo[
                ScheduledRecordingNotificationScheduler.scheduledRecordingIDKey] as? String
        completionHandler()
        Task { @MainActor in
            self.handleAction(
                actionIdentifier: actionIdentifier, scheduledRecordingIDString: scheduledRecordingIDString)
        }
    }

    /// Lets a notification still show/sound while the app is foregrounded —
    /// without this, `UNUserNotificationCenter` suppresses banners for a
    /// foregrounded app by default, which would defeat the "alarm, not
    /// silent" requirement if the user happens to have the app open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    private func handleAction(actionIdentifier: String, scheduledRecordingIDString: String?) {
        guard let scheduledRecordingIDString, let uuid = UUID(uuidString: scheduledRecordingIDString) else { return }
        let scheduledRecordingID = ScheduledRecordingID(rawValue: uuid)

        guard let coordinator else {
            pendingAction = (actionIdentifier, scheduledRecordingID)
            return
        }
        route(actionIdentifier: actionIdentifier, scheduledRecordingID: scheduledRecordingID, into: coordinator)
    }

    private func route(
        actionIdentifier: String, scheduledRecordingID: ScheduledRecordingID,
        into coordinator: ScheduledRecordingCoordinator
    ) {
        switch actionIdentifier {
        case ScheduledRecordingNotificationScheduler.startActionIdentifier:
            Task { await coordinator.handleStartAction(scheduledRecordingID: scheduledRecordingID) }
        case ScheduledRecordingNotificationScheduler.beginAtStartActionIdentifier:
            Task { await coordinator.handleBeginAtStartAction(scheduledRecordingID: scheduledRecordingID) }
        case ScheduledRecordingNotificationScheduler.skipActionIdentifier:
            Task { await coordinator.handleSkipAction(scheduledRecordingID: scheduledRecordingID) }
        case UNNotificationDefaultActionIdentifier:
            // Body tap, not a button — opens the app, never auto-starts.
            // The mandatory-interaction rule holds even here.
            break
        default:
            break
        }
    }
}
