import Foundation
import NSPCore
import NSPMedia
import NSPPersistence
import Observation

/// Owns one active capture session's UI-facing state (docs/07 §4's
/// "Active session view"). Thin by design (`CLAUDE.md` §3): every
/// durability-relevant decision — when a segment closes, when a manifest
/// seals — happens inside `CaptureEngine`/`Segmenter`; this type only
/// tracks what the screen needs to render and calls through.
///
/// `state` never reports `.recording` until `CaptureEngine.start()` has
/// already returned — and that only returns after segment 0's header is
/// durably written (Invariant I1). There is no path here that shows
/// "Recording" optimistically.
@MainActor
@Observable
public final class RecordingSession {
    public enum State: Equatable {
        case idle
        /// A `Meeting` row exists (`meetingID` is real, notes can persist)
        /// but no capture engine has started — iPad's "write a pre-brief
        /// before recording" flow (docs/07 §5, `prepareDraft`). `start()`
        /// promotes a draft in place rather than creating a second meeting.
        case draft
        case arming
        case recording
        case paused
        case finalizing
        case failed(String)
    }

    /// `internal(set)`, not `private(set)` — `RecordingSessionBrainDumpAndNote
    /// .swift` (an extension in a separate file, same target) mutates this
    /// directly, same reason `markers` below does.
    public internal(set) var state: State = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    /// `internal(set)`, not `private(set)` — `RecordingSession+Markers.swift`
    /// (an extension in a separate file, same target) mutates this
    /// directly, and Swift's `private` is file-scoped, not type-scoped.
    public internal(set) var markers: [SessionMarker] = []
    public var markerCount: Int { markers.count }
    public private(set) var meetingID: MeetingID?
    /// Set instead of `meetingID` by `startBrainDump()` — `nil` any other
    /// time, including during a `Meeting`/`Note` session. Screens that route
    /// on "is something recording right now" (`PadRootView`'s detail-column
    /// selection) check this alongside `meetingID`/`noteID` rather than
    /// assuming every active session is a `Meeting`.
    /// `internal(set)` — set from `RecordingSessionBrainDumpAndNote.swift`.
    public internal(set) var brainDumpID: BrainDumpID?
    /// Set instead of `meetingID` once `startStandaloneNote()`'s note has a
    /// recording attached — `nil` before that (a standalone note with no
    /// recording never reaches `.arming`/`.recording` at all) and any other
    /// time a `Meeting`/`BrainDump` session is active. `internal(set)` —
    /// set from `RecordingSessionBrainDumpAndNote.swift`.
    public internal(set) var noteID: NoteID?
    /// The active session's on-disk layout — `nil` outside an active
    /// session. iPad's ink canvas (`PadRecordingCanvas`) needs
    /// `inkDirectoryURL` to write `.drawing` assets; nothing else reads
    /// this today, but it's the same container `makeCaptureEngine` already
    /// built, just retained instead of staying a local to `start()`. Named
    /// for the common case (a `Meeting`); it's the same `MeetingContainer`
    /// type for a `BrainDump`/`Note` session too (`MeetingContainer`'s own
    /// doc comment on `owner`). `internal(set)` — also set from
    /// `RecordingSessionBrainDumpAndNote.swift`.
    public internal(set) var meetingContainer: MeetingContainer?
    /// Set right after a successful `stop()` when calendar sync is on and
    /// a destination calendar is chosen — `TodayView` shows
    /// `CalendarEventConfirmationView` while this is non-nil. Never set
    /// (and so never prompted) otherwise, since the whole point of the
    /// Settings toggle is that this is opt-in.
    public private(set) var pendingCalendarMeeting: Meeting?
    /// Set right after a successful `stop()` when the meeting still has the
    /// default title — `TodayView` shows `MeetingTitlePromptView` while
    /// this is non-nil. Already-titled meetings (e.g. set via the iPad
    /// canvas's title band) skip the prompt.
    public private(set) var pendingTitleMeeting: Meeting?
    /// 0...1, the "voice thermometer" docs/07 §4 calls a level meter.
    /// Only meaningful while `.recording` — `0` otherwise, including while
    /// `.paused` (the engine keeps the mic open across a pause, but
    /// showing a live meter then would read as "still recording," which
    /// isn't what `.paused` means).
    public private(set) var inputLevel: Float = 0

    // `internal` (not `private`) — the marker extension needs both; Swift's
    // `private` is file-scoped, not type-scoped.
    let environment: AppEnvironment
    var captureEngine: CaptureEngine?
    private var elapsedTimerTask: Task<Void, Never>?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Creates a real `Meeting` row and publishes `meetingID` immediately,
    /// without starting capture — iPad's pre-recording note-taking flow
    /// (docs/07 §5: "notes taken before recording starts"). `start()` later
    /// promotes this same meeting in place rather than creating a second
    /// one. Returns `nil` (leaving state untouched) if setup isn't ready.
    public func prepareDraft(title: String = RecordingSession.defaultMeetingTitle) async -> MeetingID? {
        guard state == .idle, let policy = environment.defaultPolicy else { return nil }

        let newMeetingID = MeetingID(rawValue: UUID())
        let now = environment.clock.now()
        let meeting = Meeting(
            meetingID: newMeetingID, workspaceID: policy.workspaceID, title: title, captureMode: .phone,
            originDeviceID: environment.deviceID, startedAt: now, lifecycleState: .ready, policyID: policy.policyID,
            processingMode: policy.defaultProcessingMode, availability: .complete, createdAt: now, updatedAt: now)

        do {
            try await environment.meetingRepository.insert(meeting, at: now)
            meetingContainer = try environment.makeMeetingContainer(meetingID: newMeetingID)
            meetingID = newMeetingID
            state = .draft
            return newMeetingID
        } catch {
            state = .failed(Self.describeFailure(error))
            return nil
        }
    }

    /// `existingMeetingID` promotes an arbitrary `.ready`-state `Meeting`
    /// row into a real recording — not only one this same `RecordingSession`
    /// instance drafted via `prepareDraft()` (NSP-150: "Start Recording Now"
    /// on an agenda item created directly through `AddAgendaItemFormView`,
    /// where no `prepareDraft()` call ever ran). Builds `meetingContainer`
    /// on demand when it isn't already in memory, rather than requiring the
    /// caller to have prepared one first.
    public func start(intent: RecordingIntent = .meeting, existingMeetingID: MeetingID? = nil) async {
        // A `.draft` state can now mean either a Meeting pre-brief
        // (`prepareDraft()`) or a standalone Note (`startStandaloneNote()`)
        // — recording into an existing Note draft isn't wired yet
        // (`startStandaloneNote()`'s own doc comment), so this only
        // promotes the Meeting-draft case; a Note draft falls through and
        // no-ops rather than silently spawning an unrelated new Meeting.
        guard existingMeetingID != nil || state == .idle || (state == .draft && noteID == nil) else { return }
        let draftMeetingID = existingMeetingID ?? (state == .draft ? meetingID : nil)
        state = .arming

        guard let policy = environment.defaultPolicy else {
            state = .failed("Setup isn't finished yet — try again in a moment.")
            return
        }

        do {
            let meeting: Meeting
            let container: MeetingContainer
            let fetchedDraft = try await Self.findDraft(draftMeetingID, in: environment.meetingRepository)
            if var draftMeeting = fetchedDraft {
                // Promote the draft in place — same meeting, same
                // container, so pre-recording notes stay attached rather
                // than orphaned under a discarded meetingID. Reuses an
                // already-prepared container (`prepareDraft()`'s path) or
                // builds a fresh one for a meeting this session never
                // drafted itself (`existingMeetingID`'s path).
                let draftContainer = try meetingContainer ?? environment.makeMeetingContainer(meetingID: draftMeeting.meetingID)
                draftMeeting.lifecycleState = .arming
                try await environment.meetingRepository.update(draftMeeting, at: environment.clock.now())
                meeting = draftMeeting
                container = draftContainer
            } else {
                let newMeetingID = MeetingID(rawValue: UUID())
                let now = environment.clock.now()
                let newMeeting = Meeting(
                    meetingID: newMeetingID, workspaceID: policy.workspaceID, title: Self.defaultMeetingTitle,
                    captureMode: .phone, recordingIntent: intent, originDeviceID: environment.deviceID, startedAt: now,
                    lifecycleState: .arming, policyID: policy.policyID, processingMode: policy.defaultProcessingMode,
                    availability: .complete, createdAt: now, updatedAt: now)
                try await environment.meetingRepository.insert(newMeeting, at: now)
                meeting = newMeeting
                container = try environment.makeMeetingContainer(meetingID: newMeetingID)
            }

            let engine = environment.makeCaptureEngine(owner: .meeting(meeting.meetingID), container: container)
            captureEngine = engine
            meetingContainer = container

            // Returns only after the durable write (I1) — nothing above
            // this line has said "Recording," and nothing below needed to.
            // Uses `meeting.recordingIntent`, not the `intent` parameter
            // directly, so a promoted draft (always `.meeting`, since
            // `prepareDraft` has no intent parameter of its own) keeps its
            // own tuning rather than whatever `start()` happened to be
            // called with.
            try await engine.start(micProfile: meeting.recordingIntent.microphoneProfile)

            var recordingMeeting = meeting
            recordingMeeting.lifecycleState = .recording
            try await environment.meetingRepository.update(recordingMeeting, at: environment.clock.now())

            // Satisfies NetworkGate's consent check for every meeting
            // recorded while "Sync to iCloud" is on (Settings) — the
            // human confirmation this traces back to is that explicit
            // toggle, not a silent default; this app has no separate
            // per-participant consent UI yet. Best-effort: a failed write
            // here just means this meeting won't sync, never a reason to
            // fail the recording itself.
            if recordingMeeting.processingMode != .localOnly {
                let consent = ConsentRecord(
                    consentRecordID: ConsentRecordID(rawValue: UUID()), meetingID: recordingMeeting.meetingID,
                    method: .checklistConfirmed, timestamp: environment.clock.now())
                try? await environment.consentRecordRepository.insert(consent, at: environment.clock.now())
            }

            meetingID = meeting.meetingID
            state = .recording
            startElapsedTimer(from: Date())
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    public func pause() async {
        guard state == .recording, let captureEngine else { return }
        do {
            try await captureEngine.pause()
            state = .paused
            stopElapsedTimer()
            inputLevel = 0
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    public func resume() async {
        guard state == .paused, let captureEngine else { return }
        do {
            try await captureEngine.resume()
            state = .recording
            startElapsedTimer(from: Date())
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    /// Returns to `.idle` from `.failed` so the user can retry — the only
    /// transition out of `.failed` (docs/07 §11's error-state rule: show
    /// the cause, offer a way forward, never leave a dead end).
    public func dismissFailure() {
        guard case .failed = state else { return }
        reset()
    }

    /// The current live sample position, or `nil` outside `.recording`.
    /// For continuous note-taking (iPad's ruled-paper canvas) rather than
    /// a discrete marker — see `Segmenter.currentSampleOffset()`.
    public func currentSampleOffset() async -> Int64? {
        guard state == .recording, let captureEngine else { return nil }
        return await captureEngine.currentSampleOffset()
    }

    /// The real, hardware-resolved sample rate for the active session, or
    /// `nil` before capture has started. Lets a caller convert a persisted
    /// sample offset back into seconds without guessing a rate.
    public func currentSampleRate() async -> Int? {
        guard let captureEngine else { return nil }
        return await captureEngine.resolvedAudioFormat()?.sampleRate
    }

    public func stop() async {
        guard state == .recording || state == .paused, let captureEngine else { return }
        guard meetingID != nil || brainDumpID != nil else { return }
        state = .finalizing
        stopElapsedTimer()

        do {
            let manifest = try await captureEngine.stop()
            if let meetingID {
                try await finalizeMeeting(meetingID, manifest: manifest)
            } else if let brainDumpID {
                try await finalizeBrainDump(brainDumpID, manifest: manifest)
            }
            reset()
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    /// `stop()`'s Meeting path — title/calendar prompts, AI processing, and
    /// a sync kick, none of which apply to a Brain Dump (`finalizeBrainDump`).
    private func finalizeMeeting(_ meetingID: MeetingID, manifest: Manifest) async throws {
        guard var meeting = try await environment.meetingRepository.find(meetingID) else { return }
        meeting.lifecycleState = .savedRaw
        meeting.canonicalDuration = SampleDuration(
            sampleCount: manifest.segments.reduce(Int64(0)) { $0 + $1.sampleCount },
            sampleRate: manifest.audioFormat.sampleRate)
        meeting.endedAt = environment.clock.now()
        try await environment.meetingRepository.update(meeting, at: environment.clock.now())
        // Title first, calendar second — never both sheets at once. The
        // calendar event's title should reflect what the user just typed,
        // not "Untitled meeting", so it waits for `dismissTitlePrompt` to
        // fire it instead.
        //
        // AI processing waits for the same reason when the title prompt is
        // about to show: that's also where the user picks
        // `PostRecordingProcessingOptions`, and starting the work before
        // they've answered would make those toggles meaningless.
        // `dismissTitlePrompt` fires it once they have. A meeting that's
        // already titled (e.g. the iPad canvas's title band) never shows
        // that prompt, so there's no later point to defer to — fire
        // immediately here, with everything on, matching the behavior
        // before these toggles existed.
        if meeting.title == Self.defaultMeetingTitle {
            pendingTitleMeeting = meeting
        } else {
            if environment.calendarSyncEnabled, environment.selectedCalendarIdentifier != nil {
                pendingCalendarMeeting = meeting
            }
            if let selfPersonID = environment.selfPersonID {
                let intelligence = environment.intelligenceCoordinator
                Task { await intelligence.processMeeting(meetingID, selfPersonID: selfPersonID) }
            }
        }
        // Best-effort, non-blocking — the meeting is already durably saved
        // locally (I1); sync is a fast follow on top, never a condition of
        // "saved."
        Task { await environment.syncCoordinator.syncNow(workspaceID: meeting.workspaceID) }
    }

    /// Dismisses the post-recording calendar prompt — "Skip," or after a
    /// successful "Add," either way the meeting is already saved and this
    /// is purely about closing the sheet.
    public func dismissCalendarPrompt() {
        pendingCalendarMeeting = nil
    }

    /// Dismisses the post-recording title prompt — "Skip" or after saving
    /// a real title, either way just closes the sheet. `meeting` is the
    /// (possibly retitled) meeting the caller was showing, so the calendar
    /// prompt this may chain into — held back in `stop()` for exactly this
    /// reason — shows the real title, not the placeholder.
    ///
    /// This is also where AI processing actually starts for a meeting that
    /// showed the prompt (`stop()`'s doc comment explains why it's deferred
    /// this far) — `options` defaults to everything on so an implicit
    /// dismissal (e.g. swiping the sheet away rather than tapping a button)
    /// still processes the meeting rather than silently skipping it.
    public func dismissTitlePrompt(meeting: Meeting, options: PostRecordingProcessingOptions = .init()) {
        pendingTitleMeeting = nil
        if environment.calendarSyncEnabled, environment.selectedCalendarIdentifier != nil {
            pendingCalendarMeeting = meeting
        }
        if let selfPersonID = environment.selfPersonID {
            let intelligence = environment.intelligenceCoordinator
            Task { await intelligence.processMeeting(meeting.meetingID, selfPersonID: selfPersonID, options: options) }
        }
    }

    /// The title prompt's "Delete Recording" path — clears the pending
    /// prompt without linking a calendar event or starting AI processing;
    /// the caller (`TodayPromptSheets`) is responsible for actually deleting
    /// the meeting via `AppEnvironment.deleteMeeting` first.
    public func discardPendingTitleMeeting() {
        pendingTitleMeeting = nil
    }

    public static let defaultMeetingTitle = "Untitled meeting"
    public static let defaultNoteTitle = "Untitled note"

    /// Also polls `captureEngine.levelMeter` for `inputLevel` — a 10fps
    /// cadence keeps the level meter feeling live without polling faster
    /// than a human eye needs (`AudioLevelMeter.currentLevel()` is a cheap
    /// lock-protected read, but there's no reason to call it more often
    /// than the UI repaints for it). Not `private` — Swift's `private` is
    /// file-scoped, and `RecordingSessionBrainDumpAndNote.swift` calls this
    /// too.
    func startElapsedTimer(from startedAt: Date) {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.elapsedSeconds = Date().timeIntervalSince(startedAt)
                self?.inputLevel = self?.captureEngine?.levelMeter.currentLevel() ?? 0
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    private func reset() {
        state = .idle
        elapsedSeconds = 0
        markers = []
        meetingID = nil
        brainDumpID = nil
        noteID = nil
        meetingContainer = nil
        captureEngine = nil
        inputLevel = 0
    }

    private static func findDraft(
        _ meetingID: MeetingID?, in repository: any MeetingRepository
    ) async throws -> Meeting? {
        guard let meetingID else { return nil }
        return try await repository.find(meetingID)
    }

}
