import Foundation
import NSPCore
import NSPMedia
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
        case arming
        case recording
        case paused
        case finalizing
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var markerCount = 0
    public private(set) var meetingID: MeetingID?
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

    public func start() async {
        guard state == .idle else { return }
        state = .arming

        guard let policy = environment.defaultPolicy else {
            state = .failed("Setup isn't finished yet — try again in a moment.")
            return
        }

        let newMeetingID = MeetingID(rawValue: UUID())
        let now = environment.clock.now()
        let meeting = Meeting(
            meetingID: newMeetingID, workspaceID: policy.workspaceID, title: "Untitled meeting",
            captureMode: .phone, originDeviceID: environment.deviceID, startedAt: now, lifecycleState: .arming,
            policyID: policy.policyID, processingMode: policy.defaultProcessingMode, availability: .complete,
            createdAt: now, updatedAt: now)

        do {
            try await environment.meetingRepository.insert(meeting, at: now)
            let container = try environment.makeMeetingContainer(meetingID: newMeetingID)
            let engine = environment.makeCaptureEngine(meetingID: newMeetingID, container: container)
            captureEngine = engine

            // Returns only after the durable write (I1) — nothing above
            // this line has said "Recording," and nothing below needed to.
            try await engine.start()

            var recordingMeeting = meeting
            recordingMeeting.lifecycleState = .recording
            try await environment.meetingRepository.update(recordingMeeting, at: environment.clock.now())

            meetingID = newMeetingID
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

    public func addMarker() async {
        guard state == .recording, let captureEngine else { return }
        do {
            try await captureEngine.addMarker(kind: .important)
            markerCount += 1
        } catch {
            // A missed marker warns, never stops capture (docs/03 §2.5's
            // spirit) — surfacing that warning in the UI is a follow-up.
        }
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
            }
            reset()
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

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
        markerCount = 0
        meetingID = nil
        captureEngine = nil
        inputLevel = 0
    }

    private static func describeFailure(_ error: Error) -> String {
        if let captureError = error as? CaptureEngineError {
            switch captureError {
            case .alreadyCapturing: return "Already recording."
            case .notCapturing: return "Not currently recording."
            case .backendFailure(let reason): return "Couldn't access the microphone: \(reason)"
            }
        }
        return "\(error)"
    }
}
