import Foundation
import NSPCore
import NSPMedia
import NSPPersistence

/// Brain Dump and standalone Note capture, split out of `RecordingSession
/// .swift` purely to stay under this repo's 400-line file / 250-line type
/// budgets — not a meaningful behavioral boundary, same reasoning
/// `RecordingSessionMarkers.swift`'s own split documents.
extension RecordingSession {
    /// Starts a Brain Dump — real audio capture through the same durable
    /// pipeline `start()` uses, but a `BrainDump` row, never a `Meeting`
    /// (the user's own correction: "This start[s] recording but is not a
    /// meeting"). Always begins recording immediately — unlike
    /// `prepareDraft()`/`startStandaloneNote()`, there's no "notes before
    /// recording" phase for a Brain Dump to promote out of.
    public func startBrainDump() async {
        guard state == .idle else { return }
        state = .arming

        guard let policy = environment.defaultPolicy else {
            state = .failed("Setup isn't finished yet — try again in a moment.")
            return
        }

        do {
            let newBrainDumpID = BrainDumpID(rawValue: UUID())
            let now = environment.clock.now()
            var brainDump = BrainDump(
                brainDumpID: newBrainDumpID, workspaceID: policy.workspaceID, originDeviceID: environment.deviceID,
                startedAt: now, lifecycleState: .arming, policyID: policy.policyID,
                processingMode: policy.defaultProcessingMode, createdAt: now, updatedAt: now)
            try await environment.brainDumpRepository.insert(brainDump, at: now)
            let container = try environment.makeContainer(owner: .brainDump(newBrainDumpID))

            let engine = environment.makeCaptureEngine(owner: .brainDump(newBrainDumpID), container: container)
            captureEngine = engine
            meetingContainer = container

            // A Brain Dump's own tuning, not `RecordingIntent`'s any more —
            // `RecordingIntent.mentalNote`'s old `.closeTalk` mapping moved
            // here once a mental note stopped being a `Meeting` flavor.
            try await engine.start(micProfile: .closeTalk)

            brainDump.lifecycleState = .recording
            try await environment.brainDumpRepository.update(brainDump, at: environment.clock.now())

            brainDumpID = newBrainDumpID
            state = .recording
            startElapsedTimer(from: Date())
            CaptureActivityController.shared.start(mode: .mentalNote)
        } catch {
            state = .failed(Self.describeFailure(error))
        }
    }

    /// Creates a standalone `Note` row and publishes `noteID` immediately,
    /// without starting capture — mirrors `prepareDraft()`'s "notes before
    /// recording" shape, but for a `Note` rather than a `Meeting` (a note is
    /// "a subcomponent of a meeting OR a separate/standalone component,"
    /// never a meeting itself, even once it carries a recording). Attaching
    /// a recording to this note later is follow-up work — this pass only
    /// covers the text/ink-only path the Dashboard's notes-only button
    /// needs today.
    public func startStandaloneNote(title: String = RecordingSession.defaultNoteTitle) async -> NoteID? {
        guard state == .idle, let policy = environment.defaultPolicy else { return nil }

        let newNoteID = NoteID(rawValue: UUID())
        let now = environment.clock.now()
        let note = Note(
            noteID: newNoteID, workspaceID: policy.workspaceID, title: title, startedAt: now,
            lifecycleState: .ready, policyID: policy.policyID, processingMode: policy.defaultProcessingMode,
            createdAt: now, updatedAt: now)

        do {
            try await environment.noteRepository.insert(note, at: now)
            noteID = newNoteID
            state = .draft
            return newNoteID
        } catch {
            state = .failed(Self.describeFailure(error))
            return nil
        }
    }

    /// `stop()`'s Brain Dump path — durably saves the recording and nothing
    /// else. No title/calendar prompt (a Brain Dump has neither), and no AI
    /// processing: "in the future, AI will handle these two events
    /// differently than meetings" is a forward-looking requirement, not
    /// something this pass builds — nothing processes a Brain Dump's
    /// contents yet. It also doesn't sync yet (`NSPSync`'s CloudKit zones
    /// are meeting-only today), which is strictly more conservative than
    /// I5 requires, not a gap in it. Not `private` — `stop()` (in
    /// `RecordingSession.swift`) is the only caller.
    func finalizeBrainDump(_ brainDumpID: BrainDumpID, manifest: Manifest) async throws {
        guard var brainDump = try await environment.brainDumpRepository.find(brainDumpID) else { return }
        brainDump.lifecycleState = .savedRaw
        brainDump.canonicalDuration = SampleDuration(
            sampleCount: manifest.segments.reduce(Int64(0)) { $0 + $1.sampleCount },
            sampleRate: manifest.audioFormat.sampleRate)
        brainDump.endedAt = environment.clock.now()
        try await environment.brainDumpRepository.update(brainDump, at: environment.clock.now())
    }
}
