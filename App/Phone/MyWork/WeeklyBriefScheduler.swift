import Foundation
import UserNotifications

/// Delivers the Monday-morning Weekly Brief as a moment that arrives
/// ("The Spine" recommendation, 2026-08-22) — a repeating local
/// notification, same `UNCalendarNotificationTrigger` mechanism
/// `ScheduledRecordingNotificationScheduler` uses, but `repeats: true`
/// against a weekday+time match instead of a one-shot date. Default-on for
/// every workspace: `schedule()` is idempotent (a stable identifier just
/// overwrites the pending request), so it's safe to call on every launch
/// rather than gating behind a first-run check.
enum WeeklyBriefScheduler {
    private static let identifier = "com.dexterjackson.northstarpromise.weeklyBrief"

    static func schedule() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])

        let content = UNMutableNotificationContent()
        content.title = "Your Weekly Brief is ready"
        content.body = "Threads gone quiet, people waiting on you, and this week's meeting load — all in one place."
        content.sound = .default

        var triggerComponents = DateComponents()
        triggerComponents.weekday = 2  // Monday (Sunday = 1, per Calendar.Component.weekday).
        triggerComponents.hour = 8
        triggerComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)

        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
