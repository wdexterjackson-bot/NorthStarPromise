import Foundation
import NSPCore
import NSPPersistence
import Observation
import UIKit

/// Thin App-layer orchestrator over `ScheduledRecordingRepository` and
/// `ScheduledRecordingNotificationScheduling` — same shape as
/// `AppSyncCoordinator`/`IntelligenceCoordinator`: composition and
/// persistence calls, no business logic of its own beyond what
/// `ScheduledRecordingScheduling.decision` already decided (docs/07 §2.1).
@MainActor
@Observable
public final class ScheduledRecordingCoordinator {
    private let repository: any ScheduledRecordingRepository
    private let notificationScheduler: any ScheduledRecordingNotificationScheduling
    private let projectRepository: any ProjectRepository
    private let clock: any Clock

    /// The live `RecordingSession` — late-bound because `RecordingSession`
    /// is constructed by whichever root view mounts (`PhoneRootView`/
    /// `PadRootView`), not by `AppEnvironment`, and this coordinator has to
    /// exist *before* that so a cold-launch notification response has
    /// somewhere to go. `weak` since the view layer owns the session's
    /// lifetime, not this coordinator.
    ///
    /// The `didSet` closes a narrower race than the one
    /// `NorthStarAppDelegate.pendingResponse` handles: even after
    /// `AppEnvironment`/this coordinator exist, there's a brief window
    /// before the root view's `init` has actually run and assigned a
    /// session. A Start tap arriving in that window is queued in
    /// `pendingStartID` rather than silently dropped, and flushed the
    /// moment a session shows up.
    weak var activeSession: RecordingSession? {
        didSet {
            guard activeSession != nil, let pendingStartID else { return }
            self.pendingStartID = nil
            Task { await handleStartAction(scheduledRecordingID: pendingStartID) }
        }
    }

    private var pendingStartID: ScheduledRecordingID?
    private var autoStopTask: Task<Void, Never>?
    private var armedItemID: ScheduledRecordingID?

    public init(
        repository: any ScheduledRecordingRepository,
        notificationScheduler: any ScheduledRecordingNotificationScheduling,
        projectRepository: any ProjectRepository, clock: any Clock
    ) {
        self.repository = repository
        self.notificationScheduler = notificationScheduler
        self.projectRepository = projectRepository
        self.clock = clock
    }

    /// Insert + schedule the notification as one operation — same reasoning
    /// `RecordingSession.start()` already applies to "insert meeting + start
    /// capture engine" as a unit, so a schedule and its trigger can't drift
    /// apart.
    public func create(_ item: ScheduledRecording) async throws {
        try await repository.insert(item, at: item.createdAt)
        await notificationScheduler.schedule(item)
    }

    /// Persists an edit (title/time/alert/lead-time) to an existing,
    /// not-yet-started schedule and re-registers its notification against
    /// the new details — cancel-then-reschedule, since a `UNNotificationRequest`
    /// can't be amended in place.
    public func update(_ item: ScheduledRecording) async throws {
        try await repository.update(item, at: clock.now())
        await notificationScheduler.cancel(item.scheduledRecordingID)
        await notificationScheduler.schedule(item)
    }

    public func cancelSchedule(_ item: ScheduledRecording) async throws {
        var updated = item
        updated.status = .cancelled
        try await repository.update(updated, at: clock.now())
        await notificationScheduler.cancel(item.scheduledRecordingID)
    }

    /// Called from the notification delegate's Start action. Routes
    /// through the *real* `RecordingSession.start()` — the normal Arming
    /// path, including any workspace-required announcement once that gate
    /// exists — never a shortcut around it.
    public func handleStartAction(scheduledRecordingID: ScheduledRecordingID) async {
        guard let session = activeSession else {
            pendingStartID = scheduledRecordingID
            return
        }
        guard var item = try? await repository.find(scheduledRecordingID),
            item.status == .pending || item.status == .notified
        else { return }

        await session.start()
        guard session.state == .recording, let meetingID = session.meetingID else { return }

        item.status = .started
        item.meetingID = meetingID
        try? await repository.update(item, at: clock.now())
        if let projectID = item.projectID {
            try? await projectRepository.setProjects(for: meetingID, projectIDs: [projectID])
        }
        armAutoStop(for: item, session: session)
    }

    public func handleSkipAction(scheduledRecordingID: ScheduledRecordingID) async {
        guard var item = try? await repository.find(scheduledRecordingID) else { return }
        item.status = .skipped
        try? await repository.update(item, at: clock.now())
    }

    /// The reminder's "Begin at Start Time" action — confirms the original
    /// plan rather than starting capture immediately. Deliberately does
    /// *not* start recording now and trim the lead-in afterward: once a
    /// segment is closed it's never rewritten (Invariant I3), so
    /// "discarding" pre-start audio would either violate that or just
    /// mislabel it without truly removing it — and it would mean recording
    /// audio the user didn't actually ask to capture yet. Instead this
    /// sleeps until `scheduledStart` and then runs the exact same
    /// `handleStartAction` path a live notification tap would. Wrapped in a
    /// background-task assertion for the same reason
    /// `IntelligenceCoordinator.processMeeting` is — the countdown can run
    /// past the ~30s a backgrounded app is normally guaranteed, though real
    /// survival across a long lead time while backgrounded is a hardware-
    /// validation-gated risk like the rest of this feature (docs/09
    /// NSP-149), not something this can guarantee.
    public func handleBeginAtStartAction(scheduledRecordingID: ScheduledRecordingID) async {
        guard var item = try? await repository.find(scheduledRecordingID),
            item.status == .pending || item.status == .notified
        else { return }
        item.status = .notified
        try? await repository.update(item, at: clock.now())

        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "scheduledRecordingCountdown")
        defer { UIApplication.shared.endBackgroundTask(backgroundTaskID) }

        let interval = max(0, item.scheduledStart.timeIntervalSince(clock.now()))
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        await handleStartAction(scheduledRecordingID: scheduledRecordingID)
    }

    /// Computed once, at the moment recording actually starts — a late
    /// Start tap (close to or past `scheduledStop`) just stops almost
    /// immediately rather than scheduling a negative sleep.
    private func armAutoStop(for item: ScheduledRecording, session: RecordingSession) {
        autoStopTask?.cancel()
        armedItemID = item.scheduledRecordingID
        let interval = max(0, item.scheduledStop.timeIntervalSince(clock.now()))
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.finishAutoStop(itemID: item.scheduledRecordingID, session: session)
        }
    }

    private func finishAutoStop(itemID: ScheduledRecordingID, session: RecordingSession) async {
        await session.stop()
        armedItemID = nil
        guard var item = try? await repository.find(itemID) else { return }
        item.status = .completed
        try? await repository.update(item, at: clock.now())
    }

    /// Called from the view layer's `.onChange(of: session.state)`
    /// (`PhoneRootView`/`PadRootView`) — cancels the armed auto-stop timer
    /// the moment recording ends for any reason *other* than that timer's
    /// own `stop()` call: manual Stop, a failure, a takeover from another
    /// device. Matches this codebase's existing style of the view layer
    /// calling into session-adjacent state (`dismissTitlePrompt`/
    /// `dismissCalendarPrompt`) rather than the model self-observing.
    public func recordingStateChanged(_ state: RecordingSession.State) {
        guard armedItemID != nil else { return }
        switch state {
        case .recording, .paused, .finalizing:
            return
        case .idle, .draft, .arming, .failed:
            autoStopTask?.cancel()
            autoStopTask = nil
            armedItemID = nil
        }
    }

    /// Cross-launch reconciliation — call once after `AppEnvironment
    /// .bootstrap()`. Rows past `scheduledStop` with nobody having acted
    /// become `.missed`. A `.started` row whose meeting is no longer
    /// actually recording (app killed mid-recording) is left exactly as the
    /// meeting's own lifecycle already landed — this does not attempt to
    /// solve general crash-recovery/reattachment, which appears unbuilt for
    /// ordinary recordings too.
    public func reconcile(workspaceID: WorkspaceID) async {
        guard let pending = try? await repository.fetchPending(workspaceID: workspaceID) else { return }
        let now = clock.now()
        for item in pending {
            guard ScheduledRecordingScheduling.decision(for: item, at: now) == .shouldMarkMissed else { continue }
            var updated = item
            updated.status = .missed
            try? await repository.update(updated, at: now)
            await notificationScheduler.cancel(item.scheduledRecordingID)
        }
    }
}
