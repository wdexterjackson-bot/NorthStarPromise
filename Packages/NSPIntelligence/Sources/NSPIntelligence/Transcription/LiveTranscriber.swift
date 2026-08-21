import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy
import Speech
import os.log

public enum TranscriberError: Error {
    /// No backend exists yet (`Backend/` isn't built) — `transcribeRemote`/
    /// `streamRemote` have nowhere to call.
    case unimplemented
    case authorizationDenied
}

/// Every reason a single segment can come back with zero turns — kept
/// distinct rather than collapsed into a bare `nil`, so "the recognizer
/// itself is unusable on this device" (an environment problem, most
/// commonly the on-device speech model not being downloaded — very common
/// on Simulator, per `transcribeSegment`'s own doc comment) is
/// distinguishable from "recognition ran and genuinely found nothing to
/// say" (a normal, unremarkable outcome). Both still degrade the same way
/// today (§the meeting still saves, `.partialFailure` if every segment
/// comes back empty) — this only changes what gets logged, so the next
/// time this happens it's a five-second `log show` lookup instead of a
/// multi-step audio-signal investigation.
enum SegmentTranscriptionOutcome {
    case turn(TranscriptTurn, confidence: Double)
    case recognizerUnavailable
    case recognitionError(String)
    case noSpeechDetected
}

private let logger = Logger(subsystem: "com.dexterjackson.northstarpromise", category: "LiveTranscriber")

/// The real on-device transcriber (docs/04 §2's `SpeechAnalyzerTranscriber`
/// tier, implemented against `SFSpeechRecognizer` rather than the newer
/// `SpeechAnalyzer` API — that needs iOS 26, which would raise this app's
/// iOS 18 floor; `SFSpeechRecognizer` is the broadly-available fallback the
/// same doc line anticipates ("`Speech` framework... where available").
/// Runs the canonical batch pass over already-closed segment files — never
/// live audio, no streaming (`streamOnDevice`/`streamRemote` aren't
/// implemented this pass).
public struct LiveTranscriber: TranscriberProtocol {
    private let segmentRepository: any SegmentRepository

    public init(segmentRepository: any SegmentRepository) {
        self.segmentRepository = segmentRepository
    }

    public var capabilities: TranscriberCapabilities {
        TranscriberCapabilities(
            supportedLanguages: SFSpeechRecognizer.supportedLocales().map { $0.language }, supportsWordTimings: true,
            supportsStreaming: false,
            availability: SFSpeechRecognizer()?.isAvailable == true ? .available : .unavailable)
    }

    /// Requests `Speech` framework authorization if not already determined
    /// — mirrors `EventKitCalendarEventWriter.requestAccess`'s shape. Real
    /// denial is surfaced as a thrown error rather than silently producing
    /// empty turns, so it doesn't read as "processed, nothing said."
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func transcribeOnDevice(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let granted = await Self.requestAuthorization()
            guard granted == .authorized else { throw TranscriberError.authorizationDenied }
        }

        var turns: [TranscriptTurn] = []
        var confidences: [Double] = []
        var outcomeCounts: [String: Int] = [:]
        for ref in request.segments {
            guard let segment = try await segmentRepository.find(ref.segmentID), let url = segment.localURL else {
                logger.warning("Segment \(ref.segmentID.description, privacy: .public) has no local file — skipped")
                continue
            }
            let outcome = await Self.transcribeSegment(
                fileAt: url, meetingID: request.meetingID, segmentID: segment.segmentID,
                baseSampleOffset: segment.startSample, sampleRate: segment.sampleRate)
            switch outcome {
            case .turn(let turn, let confidence):
                turns.append(turn)
                confidences.append(confidence)
                outcomeCounts["turn", default: 0] += 1
            case .recognizerUnavailable:
                outcomeCounts["recognizerUnavailable", default: 0] += 1
            case .recognitionError(let description):
                let segmentDescription = ref.segmentID.description
                logger.error("Segment \(segmentDescription, privacy: .public) failed: \(description, privacy: .public)")
                outcomeCounts["recognitionError", default: 0] += 1
            case .noSpeechDetected:
                outcomeCounts["noSpeechDetected", default: 0] += 1
            }
        }
        if turns.isEmpty, !request.segments.isEmpty {
            let segmentCount = request.segments.count
            let summary = String(describing: outcomeCounts)
            logger.error("zero turns, \(segmentCount, privacy: .public) segment(s): \(summary, privacy: .public)")
        }

        let meanConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return TranscriptionResult(
            turns: turns, languageSpans: [], meanConfidence: meanConfidence,
            provenance: Provenance(
                modelID: "SFSpeechRecognizer", modelVersion: "1", promptVersion: "n/a", generatedAt: Date(),
                processingPlane: .onDevice))
    }

    public func transcribeRemote(
        _ request: TranscriptionRequest, grant: ProcessingGrant
    ) async throws -> TranscriptionResult {
        throw TranscriberError.unimplemented
    }

    public func streamOnDevice(_ request: StreamRequest) -> AsyncThrowingStream<PartialTranscript, Error> {
        AsyncThrowingStream { $0.finish(throwing: TranscriberError.unimplemented) }
    }

    public func streamRemote(_ request: StreamRequest, grant: ProcessingGrant) -> AsyncThrowingStream<
        PartialTranscript, Error
    > {
        AsyncThrowingStream { $0.finish(throwing: TranscriberError.unimplemented) }
    }

    // MARK: - One segment

    /// One closed audio file in, one canonical `TranscriptTurn` out.
    /// `seg.timestamp`/`seg.duration` from `SFTranscriptionSegment` are
    /// seconds *within this file* — converted to the canonical sample
    /// timeline via `baseSampleOffset` (the segment's own known start),
    /// never wall-clock math (docs/03's timeline rule).
    private static func transcribeSegment(
        fileAt url: URL, meetingID: MeetingID, segmentID: SegmentID, baseSampleOffset: Int64, sampleRate: Int
    ) async -> SegmentTranscriptionOutcome {
        guard let recognizer = SFSpeechRecognizer() else {
            logger.error("SFSpeechRecognizer() returned nil — no recognizer for the current locale")
            return .recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            logger.error("SFSpeechRecognizer.isAvailable == false — recognition service isn't reachable right now")
            return .recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // A `recognitionTask` failure (most commonly `kLSRErrorDomain` code
        // 300, "failed to initialize recognizer" — the on-device speech
        // model isn't downloaded yet, a real and fairly common transient
        // state on both Simulator and a freshly set-up device) is per-
        // segment flakiness, not evidence the whole meeting is corrupt.
        // Treating it as "this segment had no usable speech" (same as
        // `result == nil`) rather than rethrowing means one segment's
        // recognizer hiccup degrades gracefully instead of failing
        // processing for the entire meeting — but the underlying reason is
        // still logged (`SegmentTranscriptionOutcome`'s own doc comment)
        // rather than discarded, so a run of these isn't a silent mystery.
        let recognizedSegments: [RecognizedSegment]
        do {
            recognizedSegments = try await withCheckedThrowingContinuation { continuation in
                let hasResumed = Lock(false)
                recognizer.recognitionTask(with: request) { result, error in
                    guard !hasResumed.exchange(true) else { return }
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        // Extract plain, Sendable data here — `SFTranscriptionSegment`
                        // itself isn't Sendable and can't cross the continuation boundary.
                        let extracted =
                            result?.bestTranscription.segments.map {
                                RecognizedSegment(
                                    text: $0.substring, timestamp: $0.timestamp, duration: $0.duration,
                                    confidence: Double($0.confidence))
                            } ?? []
                        continuation.resume(returning: extracted)
                    }
                }
            }
        } catch {
            let nsError = error as NSError
            return .recognitionError("\(nsError.domain) code \(nsError.code): \(nsError.localizedDescription)")
        }

        let tokens = recognizedSegments.map { segment -> Token in
            let start = baseSampleOffset + Int64((segment.timestamp * Double(sampleRate)).rounded())
            let end = start + Int64((segment.duration * Double(sampleRate)).rounded())
            return Token(text: segment.text, startSample: start, endSample: end, confidence: segment.confidence)
        }
        guard !tokens.isEmpty else { return .noSpeechDetected }

        let turn = TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), owner: .meeting(meetingID), revision: 1, isProvisional: false,
            tokens: tokens, segmentRefs: [segmentID])
        let meanConfidence = tokens.map(\.confidence).reduce(0, +) / Double(tokens.count)
        return .turn(turn, confidence: meanConfidence)
    }
}

/// The plain, `Sendable` fields pulled out of one `SFTranscriptionSegment`
/// — that type itself isn't `Sendable` and can't cross an actor/
/// continuation boundary.
private struct RecognizedSegment: Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double
}

/// A tiny lock-protected flag — `recognitionTask`'s completion handler is
/// technically only supposed to fire once with `shouldReportPartialResults
/// = false`, but nothing in its documented contract guarantees that, and a
/// `CheckedContinuation` resumed twice is a hard crash. Cheaper than
/// pulling in a whole actor for one flag.
private final class Lock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) { self.value = value }

    func exchange(_ newValue: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
