import Foundation
import NSPCore
import NSPIntelligence
import NSPPersistence
import UIKit

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
    private let decisionRepository: any DecisionRepository
    private let meetingRepository: any MeetingRepository
    private let clock: any Clock
    private let transcriber: LiveTranscriber
    private let summarizer = LiveOnDeviceSummarizer()
    private let embeddingIndexer: EmbeddingIndexer
    /// Guards `processMeeting` against iOS suspending the process mid-pipeline
    /// — `stop()`/`dismissTitlePrompt` kick this off as an unstructured
    /// `Task`, and without an explicit background-execution assertion, iOS
    /// gives that Task only its normal ~30s "just backgrounded" grace period
    /// before suspending it, silently dropping the transcript/summary/
    /// actions with nothing persisted and no error anywhere. One identifier
    /// at a time matches this coordinator's existing single-flight `status`
    /// property — overlapping `processMeeting` calls aren't supported today.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    public init(
        segmentRepository: any SegmentRepository, transcriptTurnRepository: any TranscriptTurnRepository,
        insightRepository: any InsightRepository, actionRepository: any ActionRepository,
        decisionRepository: any DecisionRepository, meetingRepository: any MeetingRepository, clock: any Clock,
        embedder: any EmbedderProtocol, embeddingRepository: any EmbeddingRepository
    ) {
        self.segmentRepository = segmentRepository
        self.transcriptTurnRepository = transcriptTurnRepository
        self.insightRepository = insightRepository
        self.actionRepository = actionRepository
        self.decisionRepository = decisionRepository
        self.meetingRepository = meetingRepository
        self.clock = clock
        self.transcriber = LiveTranscriber(segmentRepository: segmentRepository)
        self.embeddingIndexer = EmbeddingIndexer(embedder: embedder, embeddingRepository: embeddingRepository)
    }

    /// `selfPersonID` is a parameter, not stored — `IntelligenceCoordinator`
    /// is built in `AppEnvironment.init()`, before `bootstrap()` publishes
    /// `selfPersonID`; the caller (already past that point by the time it
    /// triggers processing) supplies the current value instead.
    ///
    /// `options` is user-chosen in `MeetingTitlePromptView`, defaulted to
    /// everything on. `!options.generateTranscript` is a full no-op — the
    /// meeting's lifecycle state is left exactly as the caller set it
    /// (`.savedRaw`), not advanced to `.processing`, since nothing here
    /// runs. Transcription is a hard prerequisite for minutes/actions, so
    /// there's no "generate minutes without a transcript" path to support.
    public func processMeeting(
        _ meetingID: MeetingID, selfPersonID: PersonID, options: PostRecordingProcessingOptions = .init()
    ) async {
        guard options.generateTranscript else { return }

        beginBackgroundTask()
        defer { endBackgroundTask() }

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

            // Best-effort — Ask's retrieval index is a derived convenience
            // (docs/04 §10.3), not something a failure here should turn
            // into a whole-pipeline error when the transcript itself, and
            // possibly minutes/actions, already succeeded.
            try? await embeddingIndexer.index(meetingID: meetingID, turns: turns, at: clock.now())

            guard options.generateMinutes || options.generateActionItems else {
                try? await Self.setLifecycleState(.readyForReview, on: meeting, in: meetingRepository, at: clock.now())
                status = .succeeded
                return
            }

            let window = TranscriptWindow(meetingID: meetingID, turns: turns)
            let didGenerateSummary = try await summarizeAndExtractActions(
                meeting: meeting, window: window, selfPersonID: selfPersonID, options: options)

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
        let segments = try await segmentRepository.fetchAll(owner: .meeting(meetingID))
        let refs = segments.map { SegmentRef(segmentID: $0.segmentID, deviceID: $0.deviceID, sequence: $0.sequence) }
        let request = TranscriptionRequest(
            meetingID: meetingID, segments: refs, expectedLanguages: [Locale.Language(identifier: "en")])
        let result = try await transcriber.transcribeOnDevice(request)
        return result.turns
    }

    /// Minutes and actions still come from one on-device model call when
    /// both are requested (matching the original, unconditional behavior) —
    /// `options` only gates which half's results get *persisted*.
    /// Independently generating just one (skipping the model call for the
    /// other) would need `summarizeOnDevice`/`extractActionCandidates`
    /// decoupled at the `LiveOnDeviceSummarizer` level, which they aren't
    /// today; out of scope here.
    ///
    /// Returns `true` if the pipeline produced usable output for what was
    /// actually requested — the caller uses that to decide `.readyForReview`
    /// vs. `.partialFailure`. When minutes were requested, that's gated on
    /// at least one insight coming back (the on-device model was
    /// available) — the same signal the original, minutes-only code used.
    /// When minutes weren't requested (actions-only), there's no
    /// model-availability signal available from this call at all — an empty
    /// candidate list is as likely to mean "no action items in this
    /// meeting" as "model unavailable" — so that combination doesn't
    /// downgrade to `.partialFailure` on an empty result.
    private func summarizeAndExtractActions(
        meeting: Meeting, window: TranscriptWindow, selfPersonID: PersonID, options: PostRecordingProcessingOptions
    ) async throws -> Bool {
        let meetingID = meeting.meetingID
        var modelProducedOutput = !options.generateMinutes

        if options.generateMinutes {
            let summarizationRequest = SummarizationRequest(
                meetingID: meetingID, transcript: window, template: Self.defaultTemplate, layers: [.executiveSummary],
                length: .standard, tone: .neutral, audience: .internalTeam,
                outputLanguages: [Locale.Language(identifier: "en")])
            let summarizationResult = try await summarizer.summarizeOnDevice(summarizationRequest)

            for draft in summarizationResult.insights {
                let insight = Insight(
                    insightID: InsightID(rawValue: UUID()), meetingID: meetingID, layer: draft.layer,
                    text: draft.text, claimKind: draft.claimKind, evidence: draft.evidence,
                    confidence: draft.confidence, provenance: summarizationResult.provenance)
                try await insightRepository.insert(insight, at: clock.now())
            }
            modelProducedOutput = !summarizationResult.insights.isEmpty

            // Decisions are a minutes concern ("what did we decide"), so
            // this rides the same `generateMinutes` toggle rather than
            // adding a third option the user never asked for. An empty
            // list doesn't affect `modelProducedOutput` — no decisions
            // being reached is a normal, common outcome, not a signal the
            // model failed.
            let decisionCandidates = try await summarizer.extractDecisionCandidates(
                from: window, transcriptRevision: 1)
            for candidate in decisionCandidates {
                let decision = Decision(
                    decisionID: DecisionID(rawValue: UUID()), meetingID: meetingID, text: candidate.text,
                    evidence: [candidate.evidence], createdBy: selfPersonID,
                    auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: clock.now())])
                try await decisionRepository.insert(decision, at: clock.now())
            }
        }

        if options.generateActionItems {
            // Action extraction only makes sense once the model is actually
            // available — an unavailable model already returns `[]` here
            // (`LiveOnDeviceSummarizer`'s own graceful-degradation shape).
            let candidates = try await summarizer.extractActionCandidates(
                from: window, transcriptRevision: 1, referenceDate: meeting.startedAt)
            for candidate in candidates {
                let action = Action(
                    actionID: ActionID(rawValue: UUID()), workspaceID: meeting.workspaceID, meetingID: meetingID,
                    text: candidate.text, date: candidate.date, evidence: [candidate.evidence],
                    createdBy: selfPersonID,
                    auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: clock.now())])
                try await actionRepository.insert(action, at: clock.now())
            }
        }

        return modelProducedOutput
    }

    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "processMeeting") { [weak self] in
            Task { @MainActor in
                self?.status = .failed("Processing was interrupted — the app was backgrounded too long")
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
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
