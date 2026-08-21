import Foundation
import NSPCore
import NSPMedia
import NSPPersistence

/// Typed, exhaustive error enum for `AudioImportCoordinator` (docs/11 §2).
enum AudioImportError: Error {
    case notReady
    case meetingNotFound
}

/// Creates a `Meeting` from an existing audio file (Voice Memos export,
/// another recorder, `.mp3`/`.wav`/`.m4a`) rather than live capture —
/// `CaptureMode.import`'s own case existed with nothing behind it until
/// now. Reuses `AudioFileImporter` (`NSPMedia`) for the actual
/// durable-write path; stops at `.savedRaw`, mirroring
/// `RecordingSession.stop()` exactly, so the caller shows the same
/// `MeetingTitlePromptView` (title, project links, processing options) an
/// import gets no special-cased shortcut around — AI processing starts
/// only once that prompt is dismissed, same as a live recording.
@MainActor
struct AudioImportCoordinator {
    let environment: AppEnvironment

    /// Imports `sourceURL` as a brand-new meeting and returns it once the
    /// audio is durably saved (I1) — no AI processing has run yet.
    func importAudio(from sourceURL: URL) async throws -> Meeting {
        guard let policy = environment.defaultPolicy else { throw AudioImportError.notReady }

        let newMeetingID = MeetingID(rawValue: UUID())
        let now = environment.clock.now()
        let meeting = Meeting(
            meetingID: newMeetingID, workspaceID: policy.workspaceID, title: RecordingSession.defaultMeetingTitle,
            captureMode: .import, originDeviceID: environment.deviceID, startedAt: now, lifecycleState: .processing,
            policyID: policy.policyID, processingMode: policy.defaultProcessingMode, availability: .complete,
            createdAt: now, updatedAt: now)
        try await environment.meetingRepository.insert(meeting, at: now)
        return try await importAudio(from: sourceURL, into: meeting)
    }

    /// Imports `sourceURL` into a `Meeting` that already exists but has no
    /// audio yet — the Today's Agenda "+" form's "don't record
    /// automatically" path (`AddAgendaItemFormView`) creates exactly this
    /// kind of bare, `.ready`-state shell, and this is how it later
    /// acquires its recording. Same durable-write path as a brand-new
    /// import, just skipping the `Meeting` insert since one already exists.
    func importAudio(from sourceURL: URL, intoExisting meetingID: MeetingID) async throws -> Meeting {
        guard let meeting = try await environment.meetingRepository.find(meetingID) else {
            throw AudioImportError.meetingNotFound
        }
        return try await importAudio(from: sourceURL, into: meeting)
    }

    private func importAudio(from sourceURL: URL, into meeting: Meeting) async throws -> Meeting {
        let container = try environment.makeMeetingContainer(meetingID: meeting.meetingID)
        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let importer = AudioFileImporter(
            audioEncoder: AVAudioFileSegmentEncoder(), segmentFileSystem: LiveSegmentFileSystem(),
            segmentRepository: environment.segmentRepository, clock: environment.clock)

        let manifest = try await importer.importFile(
            at: sourceURL, meetingID: meeting.meetingID, deviceID: environment.deviceID, container: container,
            manifestWriter: manifestWriter)

        var finished = meeting
        finished.lifecycleState = .savedRaw
        finished.canonicalDuration = SampleDuration(
            sampleCount: manifest.segments.reduce(Int64(0)) { $0 + $1.sampleCount },
            sampleRate: manifest.audioFormat.sampleRate)
        finished.endedAt = environment.clock.now()
        try await environment.meetingRepository.update(finished, at: environment.clock.now())
        return finished
    }
}
