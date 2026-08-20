import Foundation
import NSPCore
import NSPIntelligence
import NSPPersistence

/// Where the last `processMeeting` call landed. `.degraded` is an
/// expected, honest outcome when the on-device summarizer isn't available
/// (Apple Intelligence not present/enabled) — the transcript still saved,
/// matching docs/04 §1.5's "transcript only, no summary," never a bug to
/// chase.
public enum IntelligenceProcessingStatus: Equatable {
    case idle
    case processing
    case succeeded
    case degraded(reason: String)
    case failed(String)
}

/// Thin App-layer orchestrator over `NSPIntelligence`'s per-call
/// primitives — same shape as `AppSyncCoordinator`/`RecordingSession`: no
/// business logic of its own, just composition and persistence calls.
/// Runs the canonical batch pass (transcribe → persist turns → summarize →
/// ground → persist insights/actions) once, after a recording stops.
@MainActor
@Observable
public final class IntelligenceCoordinator {
    public private(set) var status: IntelligenceProcessingStatus = .idle

    private let segmentRepository: any SegmentRepository
    private let transcriptTurnRepository: any TranscriptTurnRepository
    private let insightRepository: any InsightRepository
    private let actionRepository: any ActionRepository
    private let meetingRepository: any MeetingRepository
    private let clock: any Clock
    private let transcriber: LiveTranscriber
    private let summarizer = LiveOnDeviceSummarizer()

    public init(
        segmentRepository: any SegmentRepository, transcriptTurnRepository: any TranscriptTurnRepository,
        insightRepository: any InsightRepository, actionRepository: any ActionRepository,
        meetingRepository: any MeetingRepository, clock: any Clock
    ) {
        self.segmentRepository = segmentRepository
        self.transcriptTurnRepository = transcriptTurnRepository
        self.insightRepository = insightRepository
        self.actionRepository = actionRepository
        self.meetingRepository = meetingRepository
        self.clock = clock
        self.transcriber = LiveTranscriber(segmentRepository: segmentRepository)
    }

    /// `selfPersonID` is a parameter, not stored — `IntelligenceCoordinator`
    /// is built in `AppEnvironment.init()`, before `bootstrap()` publishes
    /// `selfPersonID`; the caller (already past that point by the time it
    /// triggers processing) supplies the current value instead.
    public func processMeeting(_ meetingID: MeetingID, selfPersonID: PersonID) async {
        status = .processing
        guard var meeting = try? await meetingRepository.find(meetingID) else {
            status = .failed("Meeting not found")
            return
        }
        meeting.lifecycleState = .processing
        try? await meetingRepository.update(meeting, at: clock.now())

        do {
            let turns = try await transcribe(meetingID: meetingID)
            for turn in turns {
                try await transcriptTurnRepository.insert(turn, at: clock.now())
            }
            guard !turns.isEmpty else {
                try? await Self.setLifecycleState(.partialFailure, on: meeting, in: meetingRepository, at: clock.now())
                status = .degraded(reason: "No speech recognized")
                return
            }

            let window = TranscriptWindow(meetingID: meetingID, turns: turns)
            let didGenerateSummary = try await summarizeAndExtractActions(
                meetingID: meetingID, window: window, selfPersonID: selfPersonID)

            let finalState: MeetingState = didGenerateSummary ? .readyForReview : .partialFailure
            try? await Self.setLifecycleState(finalState, on: meeting, in: meetingRepository, at: clock.now())
            status =
                didGenerateSummary
                ? .succeeded : .degraded(reason: "Transcript only — the on-device summarizer isn't available")
        } catch {
            try? await Self.setLifecycleState(.partialFailure, on: meeting, in: meetingRepository, at: clock.now())
            status = .failed("\(error)")
        }
    }

    private func transcribe(meetingID: MeetingID) async throws -> [TranscriptTurn] {
        let segments = try await segmentRepository.fetchAll(meetingID: meetingID)
        let refs = segments.map { SegmentRef(segmentID: $0.segmentID, deviceID: $0.deviceID, sequence: $0.sequence) }
        let request = TranscriptionRequest(
            meetingID: meetingID, segments: refs, expectedLanguages: [Locale.Language(identifier: "en")])
        let result = try await transcriber.transcribeOnDevice(request)
        return result.turns
    }

    /// Returns `true` if at least one insight was actually generated (the
    /// on-device model was available) — the caller uses that to decide
    /// `.readyForReview` vs. `.partialFailure`.
    private func summarizeAndExtractActions(
        meetingID: MeetingID, window: TranscriptWindow, selfPersonID: PersonID
    ) async throws -> Bool {
        let summarizationRequest = SummarizationRequest(
            meetingID: meetingID, transcript: window, template: Self.defaultTemplate, layers: [.executiveSummary],
            length: .standard, tone: .neutral, audience: .internalTeam,
            outputLanguages: [Locale.Language(identifier: "en")])
        let summarizationResult = try await summarizer.summarizeOnDevice(summarizationRequest)

        for draft in summarizationResult.insights {
            let insight = Insight(
                insightID: InsightID(rawValue: UUID()), meetingID: meetingID, layer: draft.layer, text: draft.text,
                claimKind: draft.claimKind, evidence: draft.evidence, confidence: draft.confidence,
                provenance: summarizationResult.provenance)
            try await insightRepository.insert(insight, at: clock.now())
        }

        // Action extraction only makes sense once the model is actually
        // available — an unavailable model already returns `[]` here
        // (`LiveOnDeviceSummarizer`'s own graceful-degradation shape), so
        // no separate availability check is needed at this call site.
        let candidates = try await summarizer.extractActionCandidates(from: window, transcriptRevision: 1)
        for candidate in candidates {
            let action = Action(
                actionID: ActionID(rawValue: UUID()), meetingID: meetingID, text: candidate.text,
                evidence: [candidate.evidence], createdBy: selfPersonID,
                auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: clock.now())])
            try await actionRepository.insert(action, at: clock.now())
        }

        return !summarizationResult.insights.isEmpty
    }

    private static func setLifecycleState(
        _ state: MeetingState, on meeting: Meeting, in repository: any MeetingRepository, at date: Date
    ) async throws {
        var updated = meeting
        updated.lifecycleState = state
        try await repository.update(updated, at: date)
    }

    /// A minimal, single-section template — the full library (docs/04 §6's
    /// eleven shipped templates) is out of this pass's scope; this exists
    /// only to satisfy `SummarizationRequest.template`'s required field.
    private static let defaultTemplate = SummaryTemplate(
        templateID: "default", templateVersion: "1", sections: ["Summary"], sectionPromptFragments: [:],
        requiredLayers: [.executiveSummary], requiredFields: [], toneDefault: .neutral,
        evidenceStrictness: .standard)
}
