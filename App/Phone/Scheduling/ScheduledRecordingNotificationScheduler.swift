import Foundation
import NSPCore
import UserNotifications

/// Protocol-fronted wrapper around `UNUserNotificationCenter` so
/// `ScheduledRecordingCoordinator` never touches the real notification
/// center directly (docs/11 §4) — real delivery/timing behavior is
/// Simulator/device-manual, not unit-testable regardless.
public protocol ScheduledRecordingNotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func schedule(_ item: ScheduledRecording) async
    func cancel(_ id: ScheduledRecordingID) async
}

/// The mandatory Start/Skip notification (docs/07 §2.1) that fires at
/// `scheduledStart` — the "alarm, not a quiet banner" mechanism this
/// feature promises, built from what a third-party app can actually get
/// today (`interruptionLevel = .timeSensitive` breaks through Focus modes;
/// no special entitlement needed). True alarm-class behavior — ringing
/// through the mute switch, native sound/vibrate/silent semantics — exists
/// via AlarmKit on iOS/watchOS 26+, but this app's floor is 18.0/11.0;
/// adopting it would mean building this mechanism twice for a small slice
/// of the install base, so it's a deliberate, flagged fast-follow, not
/// adopted here (docs/07 §2.1).
struct ScheduledRecordingNotificationScheduler: ScheduledRecordingNotificationScheduling {
    static let categoryIdentifier = "SCHEDULED_RECORDING"
    static let startActionIdentifier = "SCHEDULED_RECORDING_START"
    static let skipActionIdentifier = "SCHEDULED_RECORDING_SKIP"
    static let beginAtStartActionIdentifier = "SCHEDULED_RECORDING_BEGIN_AT_START"
    static let scheduledRecordingIDKey = "scheduledRecordingID"

    /// Registers the three-action category once at launch. None carry
    /// `.foreground` — docs/07 §2's existing "begins Arming in the
    /// background" description for this same notification pattern, matching
    /// every other background-capable entry point in that table. Revisit if
    /// background-triggered start proves unreliable in testing.
    static func registerCategory() {
        let beginNow = UNNotificationAction(
            identifier: startActionIdentifier, title: "Begin Recording Now", options: [])
        let beginAtStart = UNNotificationAction(
            identifier: beginAtStartActionIdentifier, title: "Begin at Start Time", options: [])
        let cancel = UNNotificationAction(identifier: skipActionIdentifier, title: "Cancel", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: categoryIdentifier, actions: [beginNow, beginAtStart, cancel], intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]))
            ?? false
    }

    /// Fires `item.notifyLeadTime` seconds before `scheduledStart` — `0`
    /// ("None") fires exactly at the start time. The body reflects however
    /// much lead time remains so "Begin at Start Time" reads sensibly
    /// whether it's a 2:30 heads-up or a same-moment alert.
    func schedule(_ item: ScheduledRecording) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to record"
        content.body = Self.body(for: item)
        content.categoryIdentifier = Self.categoryIdentifier
        content.interruptionLevel = .timeSensitive
        content.userInfo = [Self.scheduledRecordingIDKey: item.scheduledRecordingID.rawValue.uuidString]

        switch item.alertStyle {
        case .sound:
            // `.default` today — a longer, more insistent bundled alert
            // sound (up to `UNNotificationSound`'s 30-second ceiling) is a
            // fast-follow that needs an actual audio asset added to the app
            // bundle, not something to fabricate here.
            content.sound = .default
        case .vibrateOnly, .silent:
            // Disclosed limitation (`CalendarEventReader`-style, stated
            // plainly rather than implied): `UNUserNotificationCenter` gives
            // apps no independent "force vibration without sound" toggle.
            // Whether a sound-less notification vibrates is governed by the
            // device's own Settings/Focus state, not a per-request API
            // flag — `.vibrateOnly` is best-effort under this mechanism,
            // not a hard guarantee. UI copy presenting this choice must say
            // so, not imply a promise the platform can't back.
            content.sound = nil
        }

        let notifyDate = item.scheduledStart.addingTimeInterval(-item.notifyLeadTime)
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: notifyDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: item.scheduledRecordingID.rawValue.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func body(for item: ScheduledRecording) -> String {
        guard item.notifyLeadTime > 0 else {
            return "\"\(item.title)\" is starting now — begin recording, or wait for its start time."
        }
        let minutes = Int(item.notifyLeadTime) / 60
        let seconds = Int(item.notifyLeadTime) % 60
        let leadLabel =
            seconds == 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : "\(minutes)m \(seconds)s"
        return "\"\(item.title)\" starts in \(leadLabel) — begin now, or wait for its start time."
    }

    func cancel(_ id: ScheduledRecordingID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [id.rawValue.uuidString])
    }
}
