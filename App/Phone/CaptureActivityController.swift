import ActivityKit
import Foundation

/// Starts, updates, and ends the Lock Screen / Dynamic Island Live Activity
/// that mirrors an active capture session (docs/03 §2.2). Strictly a
/// one-way *view* of `RecordingSession`/`AmbientCoordinator` state — nothing
/// here can start, stop, or otherwise affect a recording; it only publishes
/// what already happened. Lives in `App/Phone` rather than a package because
/// `ActivityKit` doesn't exist outside iOS, and this app target is where
/// every other UIKit/AVFoundation-only helper (`ScheduledRecordingCoordinator`'s
/// background task, `NorthStarPhoneApp`'s permission prompts) already lives.
///
/// One shared instance per process: only one capture session — a Meeting, a
/// Mental Note, or Exercise Mode — can be active app-wide at a time, so
/// there's never a reason for more than one live `Activity` to exist.
///
/// No interactive Stop button on the Lock Screen card yet — that needs an
/// `AppIntent` the extension can run and a way to signal `RecordingSession`/
/// `AmbientCoordinator` back in the host process (an App Group + Darwin
/// notification, most likely), which is a separate, larger piece of work.
/// Today's card is tap-to-open, same as any Live Activity without one.
@MainActor
final class CaptureActivityController {
    static let shared = CaptureActivityController()

    private var activity: Activity<CaptureActivityAttributes>?

    private init() {}

    func start(mode: CaptureActivityAttributes.Mode, startedAt: Date = Date()) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = CaptureActivityAttributes.ContentState(mode: mode, startedAt: startedAt, isPaused: false)
        activity = try? Activity.request(
            attributes: CaptureActivityAttributes(), content: .init(state: state, staleDate: nil))
    }

    /// `resumedAt` re-bases the timer's start so the Lock Screen's elapsed
    /// time reflects only the currently-running span, matching
    /// `RecordingSession.resume()`'s own `startElapsedTimer(from: Date())`
    /// rather than counting time spent paused.
    func setPaused(_ isPaused: Bool, resumedAt: Date = Date()) {
        guard let activity else { return }
        let current = activity.content.state
        let updated = CaptureActivityAttributes.ContentState(
            mode: current.mode, startedAt: isPaused ? current.startedAt : resumedAt, isPaused: isPaused)
        // `Activity` predates Swift 6 concurrency auditing and isn't
        // `Sendable`; it's documented safe to call its async methods from
        // any context, so this is a deliberate, narrow opt-out rather than
        // a real data race — same shape as `AmbientCoordinator`'s
        // `RecognitionRequestBox` uses a lock for instead, since here the
        // class's own async methods already serialize their work.
        nonisolated(unsafe) let activityToUpdate = activity
        Task { await activityToUpdate.update(.init(state: updated, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        nonisolated(unsafe) let activityToEnd = activity
        Task { await activityToEnd.end(nil, dismissalPolicy: .immediate) }
    }
}
