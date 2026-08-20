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

    /// A marker dropped during this session — a real, editable `NoteBlock`
    /// from the moment it's created (docs/07 §4, "Markers are notes, not
    /// just timestamps"), not a bare timeline dot filled in later.
    /// `elapsedSecondsAtDrop` is wall-clock, for the in-session list's
    /// display only; `block.creationRange` carries the sample-accurate
    /// anchor that's actually persisted and used for seek/evidence.
    public struct SessionMarker: Identifiable {
        public let block: NoteBlock
        public let elapsedSecondsAtDrop: TimeInterval
        public var id: NoteBlockID { block.blockID }
    }

    public private(set) var state: State = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var markers: [SessionMarker] = []
    public var markerCount: Int { markers.count }
    public private(set) var meetingID: MeetingID?
    /// The active meeting's on-disk layout — `nil` outside an active
    /// session. iPad's ink canvas (`PadRecordingCanvas`) needs
    /// `inkDirectoryURL` to write `.drawing` assets; nothing else reads
    /// this today, but it's the same container `makeCaptureEngine` already
    /// built, just retained instead of staying a local to `start()`.
    public private(set) var meetingContainer: MeetingContainer?
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

    private let environment: AppEnvironment
    private var captureEngine: CaptureEngine?
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

    public func start() async {
        guard state == .idle || state == .draft else { return }
        let draftMeetingID = state == .draft ? meetingID : nil
        state = .arming

        guard let policy = environment.defaultPolicy else {
            state = .failed("Setup isn't finished yet — try again in a moment.")
            return
        }

        do {
            let meeting: Meeting
            let container: MeetingContainer
            let fetchedDraft = try await Self.findDraft(draftMeetingID, in: environment.meetingRepository)
            if let draftContainer = meetingContainer, var draftMeeting = fetchedDraft {
                // Promote the draft in place — same meeting, same
                // container, so pre-recording notes stay attached rather
                // than orphaned under a discarded meetingID.
                draftMeeting.lifecycleState = .arming
                try await environment.meetingRepository.update(draftMeeting, at: environment.clock.now())
                meeting = draftMeeting
                container = draftContainer
            } else {
                let newMeetingID = MeetingID(rawValue: UUID())
                let now = environment.clock.now()
                let newMeeting = Meeting(
                    meetingID: newMeetingID, workspaceID: policy.workspaceID, title: Self.defaultMeetingTitle,
                    captureMode: .phone, originDeviceID: environment.deviceID, startedAt: now, lifecycleState: .arming,
                    policyID: policy.policyID, processingMode: policy.defaultProcessingMode, availability: .complete,
                    createdAt: now, updatedAt: now)
                try await environment.meetingRepository.insert(newMeeting, at: now)
                meeting = newMeeting
                container = try environment.makeMeetingContainer(meetingID: newMeetingID)
            }

            let engine = environment.makeCaptureEngine(meetingID: meeting.meetingID, container: container)
            captureEngine = engine
            meetingContainer = container

            // Returns only after the durable write (I1) — nothing above
            // this line has said "Recording," and nothing below needed to.
            try await engine.start()

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

    /// Drops a marker and immediately creates its `NoteBlock` — empty text,
    /// so the in-session marker list (`ActiveSessionCard`) can prompt the
    /// user to label it right there, or it stays unlabeled until edited
    /// from the meeting's Notes tab later. Defaults to `.action`: a marker
    /// is almost always "flag this to follow up on," and marker text is
    /// meant to be real input to summary/action generation, not a
    /// second-class annotation (docs/07 §4).
    public func addMarker() async {
        guard state == .recording, let captureEngine, let meetingID, let selfPersonID = environment.selfPersonID
        else { return }
        do {
            let sampleOffset = try await captureEngine.addMarker(kind: .actionItem)
            let now = environment.clock.now()
            let block = NoteBlock(
                blockID: NoteBlockID(rawValue: UUID()), meetingID: meetingID, authorID: selfPersonID, type: .action,
                content: .text(""), creationRange: SampleRange(startSample: sampleOffset, endSample: sampleOffset),
                privacy: .privateToAuthor,
                opLog: [
                    Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(""))
                ])
            try await environment.noteBlockRepository.insert(block, at: now)
            markers.append(SessionMarker(block: block, elapsedSecondsAtDrop: elapsedSeconds))
        } catch {
            // A missed marker warns, never stops capture (docs/03 §2.5's
            // spirit) — surfacing that warning in the UI is a follow-up.
        }
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

    /// Labels a marker from the in-session list. Editing an existing
    /// `NoteBlock`'s content is the same operation `NotesTab`'s composer
    /// does post-hoc — this is just that same edit, offered at the moment
    /// the user is most likely to remember what the marker was for.
    public func labelMarker(_ marker: SessionMarker, text: String) async {
        guard let index = markers.firstIndex(where: { $0.id == marker.id }), let selfPersonID = environment.selfPersonID
        else { return }
        var block = markers[index].block
        let now = environment.clock.now()
        block.content = .text(text)
        block.opLog.append(
            Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(text)))
        do {
            try await environment.noteBlockRepository.update(block, at: now)
            markers[index] = SessionMarker(block: block, elapsedSecondsAtDrop: markers[index].elapsedSecondsAtDrop)
        } catch {
            // The label just doesn't stick this time; the marker itself
            // (and its timestamp) is unaffected — never worth failing the
            // recording over.
        }
    }

    public func deleteMarker(_ marker: SessionMarker) async {
        do {
            try await environment.noteBlockRepository.delete(marker.id)
            markers.removeAll { $0.id == marker.id }
        } catch {
            // Leave it in the list rather than silently pretending the
            // delete happened.
        }
    }

    private static func millisecondTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    public func stop() async {
        guard state == .recording || state == .paused, let captureEngine, let meetingID else { return }
        state = .finalizing
        stopElapsedTimer()

        do {
            let manifest = try await captureEngine.stop()
            if var meeting = try await environment.meetingRepository.find(meetingID) {
                meeting.lifecycleState = .savedRaw
                meeting.canonicalDuration = SampleDuration(
                    sampleCount: manifest.segments.reduce(Int64(0)) { $0 + $1.sampleCount },
                    sampleRate: manifest.audioFormat.sampleRate)
                meeting.endedAt = environment.clock.now()
                try await environment.meetingRepository.update(meeting, at: environment.clock.now())
                // Title first, calendar second — never both sheets at once.
                // The calendar event's title should reflect what the user
                // just typed, not "Untitled meeting", so it waits for
                // `dismissTitlePrompt` to fire it instead.
                if meeting.title == Self.defaultMeetingTitle {
                    pendingTitleMeeting = meeting
                } else if environment.calendarSyncEnabled, environment.selectedCalendarIdentifier != nil {
                    pendingCalendarMeeting = meeting
                }
                // Best-effort, non-blocking — the meeting is already
                // durably saved locally (I1); sync and processing are both
                // fast follows on top, never a condition of "saved."
                Task { await environment.syncCoordinator.syncNow(workspaceID: meeting.workspaceID) }
                if let selfPersonID = environment.selfPersonID {
                    let intelligence = environment.intelligenceCoordinator
                    Task { await intelligence.processMeeting(meetingID, selfPersonID: selfPersonID) }
                }
            }
            reset()
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    /// Dismisses the post-recording calendar prompt — "Skip," or after a
    /// successful "Add," either way the meeting is already saved and this
    /// is purely about closing the sheet.
    public func dismissCalendarPrompt() {
        pendingCalendarMeeting = nil
    }

    /// Dismisses the post-recording title prompt — "Skip" or after saving
    /// a real title, either way just closes the sheet. Processing already
    /// started independently in `stop()`, not gated on this. `meeting` is
    /// the (possibly retitled) meeting the caller was showing, so the
    /// calendar prompt this may chain into — held back in `stop()` for
    /// exactly this reason — shows the real title, not the placeholder.
    public func dismissTitlePrompt(meeting: Meeting) {
        pendingTitleMeeting = nil
        if environment.calendarSyncEnabled, environment.selectedCalendarIdentifier != nil {
            pendingCalendarMeeting = meeting
        }
    }

    public static let defaultMeetingTitle = "Untitled meeting"

    /// Also polls `captureEngine.levelMeter` for `inputLevel` — a 10fps
    /// cadence keeps the level meter feeling live without polling faster
    /// than a human eye needs (`AudioLevelMeter.currentLevel()` is a cheap
    /// lock-protected read, but there's no reason to call it more often
    /// than the UI repaints for it).
    private func startElapsedTimer(from startedAt: Date) {
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
