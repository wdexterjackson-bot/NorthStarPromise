import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy
import Speech

public enum TranscriberError: Error {
    /// No backend exists yet (`Backend/` isn't built) — `transcribeRemote`/
    /// `streamRemote` have nowhere to call.
    case unimplemented
    case authorizationDenied
}

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
        for ref in request.segments {
            guard let segment = try await segmentRepository.find(ref.segmentID), let url = segment.localURL else {
                continue
            }
            guard
                let (turn, confidence) = try await Self.transcribeSegment(
                    fileAt: url, meetingID: request.meetingID, segmentID: segment.segmentID,
                    baseSampleOffset: segment.startSample, sampleRate: segment.sampleRate)
            else { continue }
            turns.append(turn)
            confidences.append(confidence)
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
    ) async throws -> (TranscriptTurn, Double)? {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let recognizedSegments: [RecognizedSegment] = try await withCheckedThrowingContinuation { continuation in
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

        let tokens = recognizedSegments.map { segment -> Token in
            let start = baseSampleOffset + Int64((segment.timestamp * Double(sampleRate)).rounded())
            let end = start + Int64((segment.duration * Double(sampleRate)).rounded())
            return Token(text: segment.text, startSample: start, endSample: end, confidence: segment.confidence)
        }
        guard !tokens.isEmpty else { return nil }

        let turn = TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: UUID()), meetingID: meetingID, revision: 1, isProvisional: false,
            tokens: tokens, segmentRefs: [segmentID])
        let meanConfidence = tokens.map(\.confidence).reduce(0, +) / Double(tokens.count)
        return (turn, meanConfidence)
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
