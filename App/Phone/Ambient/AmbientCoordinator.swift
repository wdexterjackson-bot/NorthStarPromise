import AVFoundation
import Foundation
import NSPCore
import NSPIntelligence
import Observation
import Speech

/// Ambient Mode's live session ("Overheard" recommendation, 2026-08-22).
/// Deliberately **not** `RecordingSession`/`CaptureEngine` — this never
/// writes an audio file, never produces a `Meeting` or `Segment`, and
/// nothing here is durable except a suggestion's own short text excerpt
/// once a human accepts it. Continuous on-device speech recognition
/// (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`) feeds a
/// rolling in-memory text buffer through `AmbientRelevanceGating` and
/// `AmbientExtracting`; almost everything is discarded before it's ever
/// looked at twice.
///
/// **Needs on-device verification before shipping** — same caveat every
/// other live-capture path in this codebase carries (`CLAUDE.md` §7): this
/// environment has no way to speak into a microphone or observe real
/// recognition results, so the audio-session/recognition-restart plumbing
/// below is written to the documented `SFSpeechRecognizer` contract but
/// unverified on hardware.
///
/// **Foreground-only today.** `project.yml` declares no `UIBackgroundModes`
/// entry — same open risk `NSP-149` (Scheduled Recording) already flags
/// for its own auto-stop timer, not silently assumed away here either.
/// Without it, iOS suspends this session shortly after the app leaves the
/// foreground; a genuinely hours-long "listen while you go about your day"
/// session needs that entitlement added deliberately, with the same
/// App-Review-scrutiny tradeoff `NSP-149`'s own ticket text calls out, not
/// as a side effect of this feature landing.
@MainActor
@Observable
public final class AmbientCoordinator {
    public enum State: Equatable {
        case idle
        case listening
        /// The chosen duration elapsed; waiting for an explicit "Continue
        /// Ambient Mode?" answer — never a silent stop, never a silent
        /// continuation (locked decision, 2026-08-22).
        case awaitingContinuePrompt
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    /// How many suggestions this session has produced so far — a light,
    /// honest "N caught" indicator; never a claim about what was said.
    public private(set) var suggestionsThisSession: Int = 0

    private let environment: AppEnvironment
    private let relevanceGate: any AmbientRelevanceGating
    private let extractor: any AmbientExtracting
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()

    /// A stable box the audio tap captures once, at install time — its
    /// *identity* never changes across recognition-task rotations, only
    /// which underlying request it forwards buffers to. See
    /// `RecognitionRequestBox`'s own doc comment for why this indirection
    /// exists at all.
    private let requestBox = RecognitionRequestBox()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var rotationTimerTask: Task<Void, Never>?
    private var durationTimerTask: Task<Void, Never>?
    private var elapsedTimerTask: Task<Void, Never>?
    private var lastEvaluatedLength: Int = 0
    private var sessionStartedAt: Date?
    private var chosenDurationMinutes: Int = 60

    /// A recognition task is restarted this often — `SFSpeechRecognizer`'s
    /// on-device sessions aren't documented to run indefinitely; refreshing
    /// well inside any practical limit keeps hours-long ambient sessions
    /// alive rather than silently going stale mid-afternoon.
    private static let recognitionRotationInterval: TimeInterval = 50

    public init(
        environment: AppEnvironment, relevanceGate: any AmbientRelevanceGating = HeuristicAmbientRelevanceGate(),
        extractor: any AmbientExtracting = HeuristicAmbientExtractor()
    ) {
        self.environment = environment
        self.relevanceGate = relevanceGate
        self.extractor = extractor
    }

    public static func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    public func start(durationMinutes: Int) async {
        guard state == .idle else { return }
        guard await Self.requestAuthorization() else {
            state = .failed("Microphone or speech recognition access wasn't granted.")
            return
        }

        chosenDurationMinutes = durationMinutes
        do {
            try beginCapture()
        } catch {
            state = .failed("Couldn't start Ambient Mode: \(error.localizedDescription)")
            return
        }

        sessionStartedAt = Date()
        state = .listening
        announceIfRequired()
        startElapsedTimer()
        startDurationTimer()
    }

    /// "Continue Ambient Mode?" → Yes — restarts the duration clock.
    public func continueSession() {
        guard state == .awaitingContinuePrompt else { return }
        state = .listening
        announceIfRequired()
        startDurationTimer()
    }

    public func stop() {
        rotationTimerTask?.cancel()
        durationTimerTask?.cancel()
        elapsedTimerTask?.cancel()
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.swap(to: nil)?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        state = .idle
        elapsedSeconds = 0
        suggestionsThisSession = 0
        lastEvaluatedLength = 0
        sessionStartedAt = nil
    }

    /// Same audible-announcement mechanism meeting recording already has
    /// (`Policy.announcementRequired`, docs/06 §3.2) — Ambient Mode isn't a
    /// separate consent surface, it reuses this workspace's existing
    /// setting rather than forcing its own.
    private func announceIfRequired() {
        guard environment.defaultPolicy?.announcementRequired == true else { return }
        speak("Recording in Process")
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Capture

    private func beginCapture() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [requestBox] buffer, _ in
            requestBox.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        try startRecognitionTask()
        startRotationTimer()
    }

    /// Swaps in a brand-new `SFSpeechAudioBufferRecognitionRequest` +
    /// recognition task without touching the audio tap — the tap always
    /// feeds whatever `requestBox` currently holds, so rotating the
    /// underlying request never drops a buffer between the old task ending
    /// and the new one starting.
    private func startRecognitionTask() throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw AmbientCoordinatorError.recognizerUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        requestBox.swap(to: request)?.endAudio()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.evaluate(fullText: text) }
        }
    }

    private func startRotationTimer() {
        rotationTimerTask?.cancel()
        rotationTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.recognitionRotationInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.rotateRecognitionTask()
            }
        }
    }

    private func rotateRecognitionTask() async {
        guard state == .listening else { return }
        let previousTask = recognitionTask
        do {
            // `startRecognitionTask` swaps in the new request and returns
            // the just-replaced one already ended, via `requestBox.swap`.
            try startRecognitionTask()
        } catch {
            state = .failed("Ambient Mode lost the recognizer: \(error.localizedDescription)")
            stop()
            return
        }
        previousTask?.cancel()
        lastEvaluatedLength = 0
    }

    // MARK: - Relevance + extraction

    /// Called on every partial/final recognition update — evaluates only
    /// the *newly recognized* suffix so the same words aren't re-gated
    /// repeatedly as a sentence keeps growing.
    private func evaluate(fullText: String) {
        guard fullText.count > lastEvaluatedLength else { return }
        lastEvaluatedLength = fullText.count
        let window = AmbientWindow(text: fullText, capturedAt: Date())
        guard relevanceGate.isRelevant(window) else { return }
        Task { await self.produceSuggestion(from: window) }
    }

    private func produceSuggestion(from window: AmbientWindow) async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        let knownPeople = (try? await environment.personRepository.fetchAll(workspaceID: workspaceID)) ?? []
        let knownThreads = (try? await environment.threadRepository.fetchAll(workspaceID: workspaceID)) ?? []
        let result = extractor.extract(window, knownPeople: knownPeople, knownThreads: knownThreads)

        let now = environment.clock.now()
        let suggestion = AmbientSuggestion(
            ambientSuggestionID: .generate(clock: environment.clock), workspaceID: workspaceID, kind: result.kind,
            text: result.text, threadID: result.threadID, counterpartyID: result.counterpartyID,
            evidence: AmbientEvidence(excerpt: window.text, capturedAt: window.capturedAt), createdAt: now,
            updatedAt: now)
        try? await environment.ambientSuggestionRepository.insert(suggestion, at: now)
        suggestionsThisSession += 1
    }

    // MARK: - Timers

    private func startElapsedTimer() {
        elapsedTimerTask?.cancel()
        let startedAt = Date()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.elapsedSeconds = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startDurationTimer() {
        durationTimerTask?.cancel()
        let deadline = Date().addingTimeInterval(TimeInterval(chosenDurationMinutes * 60))
        durationTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date() >= deadline {
                    self.state = .awaitingContinuePrompt
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

enum AmbientCoordinatorError: Error {
    case recognizerUnavailable
}

/// A small locked box with a stable *identity* holding a swappable
/// *current* `SFSpeechAudioBufferRecognitionRequest` — the audio tap
/// closure captures this box exactly once, at install time, and every
/// buffer forwards to whichever request `swap(to:)` most recently made
/// current. This indirection is what lets recognition tasks rotate every
/// `recognitionRotationInterval` without ever reinstalling the tap or
/// dropping a buffer in the gap between an old task ending and a new one
/// starting. The tap's callback runs on a real-time audio thread, not
/// `MainActor`, so this needs thread-safe access independent of the
/// coordinator's own actor isolation — same "cheaper than an actor for one
/// piece of shared state" reasoning `LiveTranscriber`'s own `Lock` helper
/// uses.
private final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    /// Installs `newRequest` as current and returns whatever was current
    /// before — the caller is responsible for calling `.endAudio()` on the
    /// returned request once it's done with it.
    @discardableResult
    func swap(to newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = newRequest
        return old
    }
}
