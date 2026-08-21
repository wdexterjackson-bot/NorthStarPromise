import Foundation

/// What, if anything, should happen to a `ScheduledRecording` right now.
/// The only place "is this due" is decided — every caller (notification
/// scheduling, auto-stop, cross-launch reconciliation) acts on this and
/// carries no decision logic of its own.
public enum ScheduledRecordingDecision: Sendable, Hashable {
    /// Nothing to do yet.
    case notYetDue
    /// `now` has reached the notify point (`scheduledStart - notifyLeadTime`)
    /// and the local notification hasn't been scheduled/delivered yet.
    case shouldNotify
    /// Recording is live (`status == .started`) and `now` has reached
    /// `scheduledStop` — fire the unattended auto-stop.
    case shouldAutoStop
    /// `now` has passed `scheduledStop` and nobody ever acted on the
    /// notification (still `.pending`/`.notified`) — the window closed
    /// with no Start/Skip.
    case shouldMarkMissed
    /// `.completed`/`.skipped`/`.missed`/`.cancelled` — resolved, nothing
    /// left to decide.
    case terminal
}

/// Pure, `Date`-parameterized — no I/O, no `UNUserNotificationCenter`, no
/// GRDB. Same shape as `MeetingLifecycle`'s transition function: given a
/// state and a moment in time, what should happen. `Date` arithmetic is
/// confined to this file and the App-layer coordinator that calls it —
/// never `NSPMedia`'s capture/timeline code, which stays monotonic-sample-
/// count-only as always (`docs/11` §4).
public enum ScheduledRecordingScheduling {
    public static func decision(for item: ScheduledRecording, at now: Date) -> ScheduledRecordingDecision {
        switch item.status {
        case .completed, .skipped, .missed, .cancelled:
            return .terminal

        case .started:
            return now >= item.scheduledStop ? .shouldAutoStop : .notYetDue

        case .pending, .notified:
            if now >= item.scheduledStop {
                return .shouldMarkMissed
            }
            if item.status == .pending, now >= item.scheduledStart.addingTimeInterval(-item.notifyLeadTime) {
                return .shouldNotify
            }
            return .notYetDue
        }
    }
}
