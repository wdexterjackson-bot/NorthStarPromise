import EventKit
import Foundation
import NSPActions
import NSPCore
import NSPIntelligence
import NSPPersistence
import NSPPolicy

/// The construction-time factory helpers `AppEnvironment.init()` calls —
/// pulled into their own file purely to keep `AppEnvironment.swift` under
/// this repo's 400-line file-length budget. Not `private` (extension
/// members in a different file can't be) — internal access is fine since
/// none of this is meant to be called from outside `App/Phone` anyway.
extension AppEnvironment {
    /// Named type in place of a many-member tuple (SwiftLint's
    /// `large_tuple` rule caps tuples at 2) for Ask's construction-time
    /// dependencies — pulled into its own factory purely to keep `init`
    /// under this repo's 50-line function-body budget.
    struct AskDependencies {
        let embedder: any EmbedderProtocol
        let embeddingRepository: any EmbeddingRepository
        let ftsQueryService: any FTSQueryService
        let askAnswerer: any AskAnswerer
        let askAuthorizationResolver: AskAuthorizationResolver
    }

    static func makeAskDependencies(
        _ appDatabase: AppDatabase, repositories: CoreRepositories, deviceID: DeviceID
    ) -> AskDependencies {
        AskDependencies(
            embedder: OnDeviceEmbedder(), embeddingRepository: GRDBEmbeddingRepository(dbWriter: appDatabase.dbWriter),
            ftsQueryService: GRDBFTSQueryService(dbWriter: appDatabase.dbWriter),
            askAnswerer: LiveOnDeviceAskAnswerer(),
            askAuthorizationResolver: AskAuthorizationResolver(
                meetingRepository: repositories.meeting, projectRepository: repositories.project,
                currentDeviceID: deviceID))
    }

    /// Named type in place of a many-member tuple, same reasoning as
    /// `AskDependencies` above — pulled into its own factory purely to keep
    /// `init` under this repo's 50-line function-body budget.
    struct Coordinators {
        let sync: AppSyncCoordinator
        let intelligence: IntelligenceCoordinator
        let scheduledRecording: ScheduledRecordingCoordinator
    }

    static func makeCoordinators(
        repositories: CoreRepositories, ask: AskDependencies, clock: any Clock,
        notificationScheduler: any ScheduledRecordingNotificationScheduling, networkGate: any NetworkGate
    ) -> Coordinators {
        Coordinators(
            sync: AppSyncCoordinator(
                networkGate: networkGate, meetingRepository: repositories.meeting,
                segmentRepository: repositories.segment),
            intelligence: IntelligenceCoordinator(
                segmentRepository: repositories.segment, transcriptTurnRepository: repositories.transcriptTurn,
                insightRepository: repositories.insight, actionRepository: repositories.action,
                decisionRepository: repositories.decision, meetingRepository: repositories.meeting, clock: clock,
                embedder: ask.embedder, embeddingRepository: ask.embeddingRepository),
            scheduledRecording: ScheduledRecordingCoordinator(
                repository: repositories.scheduledRecording, notificationScheduler: notificationScheduler,
                projectRepository: repositories.project, clock: clock))
    }

    static func makeNetworkGate(repositories: CoreRepositories, clock: any Clock) -> any NetworkGate {
        DefaultNetworkGate(
            auditRecorder: PersistedAuditEventRecorder(repository: repositories.auditEvent, clock: clock),
            consentLookup: PersistedConsentRecordLookup(repository: repositories.consentRecord),
            policyLookup: PersistedPolicySnapshotLookup(
                meetingRepository: repositories.meeting, policyRepository: repositories.policy))
    }

    /// Named type in place of a many-member tuple (SwiftLint's
    /// `large_tuple` rule caps tuples at 2) for the repositories that get
    /// reused across several other constructions below, not just assigned
    /// straight to `self`.
    struct CoreRepositories {
        let meeting: any MeetingRepository
        let segment: any SegmentRepository
        let policy: any PolicyRepository
        let consentRecord: any ConsentRecordRepository
        let auditEvent: any AuditEventRepository
        let transcriptTurn: any TranscriptTurnRepository
        let insight: any InsightRepository
        let action: any ActionRepository
        let scheduledRecording: any ScheduledRecordingRepository
        let project: any ProjectRepository
        let decision: any DecisionRepository
        let meetingAttendee: any MeetingAttendeeRepository
        let thread: any NSPThreadRepository
        let brainDump: any BrainDumpRepository
        let note: any NoteRepository
    }

    static func makeCoreRepositories(_ appDatabase: AppDatabase) -> CoreRepositories {
        let dbWriter = appDatabase.dbWriter
        return CoreRepositories(
            meeting: GRDBMeetingRepository(dbWriter: dbWriter), segment: GRDBSegmentRepository(dbWriter: dbWriter),
            policy: GRDBPolicyRepository(dbWriter: dbWriter),
            consentRecord: GRDBConsentRecordRepository(dbWriter: dbWriter),
            auditEvent: GRDBAuditEventRepository(dbWriter: dbWriter),
            transcriptTurn: GRDBTranscriptTurnRepository(dbWriter: dbWriter),
            insight: GRDBInsightRepository(dbWriter: dbWriter), action: GRDBActionRepository(dbWriter: dbWriter),
            scheduledRecording: GRDBScheduledRecordingRepository(dbWriter: dbWriter),
            project: GRDBProjectRepository(dbWriter: dbWriter), decision: GRDBDecisionRepository(dbWriter: dbWriter),
            meetingAttendee: GRDBMeetingAttendeeRepository(dbWriter: dbWriter),
            thread: GRDBNSPThreadRepository(dbWriter: dbWriter),
            brainDump: GRDBBrainDumpRepository(dbWriter: dbWriter), note: GRDBNoteRepository(dbWriter: dbWriter))
    }

    static func loadAppearanceMode() -> AppearanceMode {
        UserDefaults.standard.string(forKey: "com.dexterjackson.northstarpromise.appearanceMode")
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    static func loadOrCreateDeviceID() -> DeviceID {
        let key = "com.dexterjackson.northstarpromise.deviceID"
        if let stored = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return DeviceID(rawValue: uuid)
        }
        let fresh = DeviceID(rawValue: UUID())
        UserDefaults.standard.set(fresh.rawValue.uuidString, forKey: key)
        return fresh
    }

    /// Resolves both of `init()`'s top-level sandbox directories in one
    /// call — folded together purely to keep `init()` under this repo's
    /// 50-line function-body budget, not because the two are conceptually
    /// related (`appSupportURL` is the private segment/manifest store every
    /// `MeetingContainer` builds from; the second is the user-browsable
    /// import/export folder, see `ensureDefaultImportExportDirectory`'s own
    /// doc comment below).
    static func resolveStorageDirectories() throws -> (appSupportURL: URL, defaultImportExportDirectoryURL: URL?) {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return (appSupportURL, ensureDefaultImportExportDirectory())
    }

    /// Every installation's default import/export location — a "North-Star
    /// Promise" folder inside the app's `Documents` directory (not
    /// `Application Support`, which every `MeetingContainer` uses instead
    /// for the private, non-user-browsable segment/manifest store —
    /// `containerRootURL`'s own doc comment). `Documents` plus
    /// `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`
    /// (`Info.plist`) is what makes a folder show up in the on-device Files
    /// app under "On My iPhone/iPad" → North-Star Promise, so a user can
    /// drop a recording in from Finder/AirDrop, not only through this app's
    /// own `.fileImporter` picker. Idempotent — safe to call on every
    /// launch, matching `MeetingContainer.ensureDirectoryStructure`'s own
    /// "safe to call every launch" contract.
    private static func ensureDefaultImportExportDirectory() -> URL? {
        guard
            let documentsURL = try? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else {
            return nil
        }
        let folderURL = documentsURL.appendingPathComponent("North-Star Promise", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
