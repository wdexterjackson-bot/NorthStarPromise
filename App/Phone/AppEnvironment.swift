import EventKit
import Foundation
import NSPActions
import NSPCore
import NSPIntelligence
import NSPMedia
import NSPPersistence
import NSPPolicy
import Observation

/// The app's composition root — construction and wiring only, no
/// business logic (`CLAUDE.md` §3: "app targets contain no business
/// logic"). Every screen reads its dependencies from this one place
/// rather than constructing its own database connection or repository.
@MainActor
@Observable
public final class AppEnvironment {
    public let appDatabase: AppDatabase
    public let meetingRepository: any MeetingRepository
    public let segmentRepository: any SegmentRepository
    public let timelineEventRepository: any TimelineEventRepository
    public let noteBlockRepository: any NoteBlockRepository
    public let policyRepository: any PolicyRepository
    public let workspaceRepository: any WorkspaceRepository
    public let personRepository: any PersonRepository
    public let actionRepository: any ActionRepository
    public let consentRecordRepository: any ConsentRecordRepository
    public let auditEventRepository: any AuditEventRepository
    public let transcriptTurnRepository: any TranscriptTurnRepository
    public let insightRepository: any InsightRepository
    public let calendarEventWriter: any CalendarEventWriter
    public let calendarEventReader: any CalendarEventReader
    public let scheduledRecordingRepository: any ScheduledRecordingRepository
    public let projectRepository: any ProjectRepository
    public let decisionRepository: any DecisionRepository
    /// People's attendee data (`Person`'s own doc comment) and Threads'
    /// storyline grouping — see `Project`'s and `NSPThread`'s doc comments
    /// for how the two independent groupings differ.
    public let meetingAttendeeRepository: any MeetingAttendeeRepository
    public let threadRepository: any NSPThreadRepository
    /// People plan phase 2 (2026-08-22): tracking who's relevant to a
    /// Thread/Project beyond meeting attendance.
    public let threadParticipantRepository: any ThreadParticipantRepository
    public let projectPersonRepository: any ProjectPersonRepository
    public let brainDumpRepository: any BrainDumpRepository
    public let noteRepository: any NoteRepository
    /// Recurring events (NSP-157).
    public let recurrenceRuleRepository: any RecurrenceRuleRepository
    public let recurrenceExceptionRepository: any RecurrenceExceptionRepository
    /// System-suggested threads' dismissal memory (`ThreadsListView`'s
    /// "Suggested" section) — see `ThreadSuggestionDismissalRepository`'s
    /// own doc comment for why the fingerprint is opaque at this layer.
    public let threadSuggestionDismissalRepository: any ThreadSuggestionDismissalRepository
    public let inkAssetFileSystem: any InkAssetFileSystem
    /// Ask's retrieval half (docs/04 §10.3) — `embedder`/`embeddingRepository`
    /// also back `IntelligenceCoordinator`'s post-recording indexing, so
    /// both live here rather than being constructed twice.
    public let embedder: any EmbedderProtocol
    public let embeddingRepository: any EmbeddingRepository
    public let ftsQueryService: any FTSQueryService
    /// Ask's answering half (docs/04 §10.4).
    public let askAnswerer: any AskAnswerer
    /// Not `AskCoordinator` itself — that's constructed by the view layer
    /// once `defaultPolicy` is known, same lifecycle `RecordingSession`
    /// already follows (`AskCoordinator`'s own doc comment explains why a
    /// `HybridRetriever` can't be built this early).
    public let askAuthorizationResolver: AskAuthorizationResolver
    /// The single I5 choke point (docs/06 §2) — every `NSPSync` write
    /// already calls this internally; `syncCoordinator` below is the only
    /// thing in `App/Phone` that needs it directly.
    public let networkGate: any NetworkGate
    public let syncCoordinator: AppSyncCoordinator
    public let intelligenceCoordinator: IntelligenceCoordinator
    public let scheduledRecordingCoordinator: ScheduledRecordingCoordinator
    /// Off until wired to a remote-config/build-setting-backed provider —
    /// `AllFlagsOffProvider` keeps every `FeatureFlag` off by default
    /// (`CLAUDE.md` §5.8).
    public let featureFlagProvider: any FeatureFlagProviding

    public let containerRootURL: URL
    /// The "North-Star Promise" folder every installation creates in its
    /// `Documents` directory (`AppEnvironmentFactories.resolveStorageDirectories`)
    /// — visible in the on-device Files app, the default place a user drops
    /// a recording in for import. Unlike `containerRootURL`, this has
    /// nothing to do with a meeting's durable segment/manifest storage; it
    /// only exists so imports/exports have one well-known, user-browsable
    /// home. `nil` only if `Documents` itself couldn't be resolved — never
    /// blocks app launch.
    public let defaultImportExportDirectoryURL: URL?
    public let deviceID: DeviceID
    public let clock: any Clock

    /// "Create a calendar event for recordings" (Settings § Calendar).
    /// Off by default — this only ever runs after the user opts in, and
    /// each event still gets a human confirmation before it's created
    /// (I6; see `CalendarEventConfirmationView`).
    public var calendarSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarSyncEnabled, forKey: Self.calendarSyncEnabledKey) }
    }
    /// Which calendar new events go into. `nil` until the user picks one
    /// (Settings fetches `calendarEventWriter.availableCalendars()` and
    /// defaults to the first once access is granted).
    public var selectedCalendarIdentifier: String? {
        didSet { UserDefaults.standard.set(selectedCalendarIdentifier, forKey: Self.selectedCalendarIdentifierKey) }
    }

    /// Settings' explicit dark-mode override (docs/07's own instruction:
    /// the Dashboard's design system ships both themes on both devices —
    /// §2.1 of `DASHBOARD_SPEC.md` — and Settings must let the user pin one
    /// rather than only following the system). `.system` means "no
    /// override" — `RootView` applies this via `.preferredColorScheme(_:)`
    /// at the very top of the view tree so it wins over the OS setting
    /// everywhere, not just on screens re-skinned to the new design system.
    public var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }

    /// The one local workspace/policy this build creates on first launch
    /// (docs/06 §1.1's safest default: `.localOnly`). Multi-workspace
    /// creation/switching UI doesn't exist yet — every meeting Arms
    /// against this policy until it does. `nil` until `bootstrap()`
    /// completes; screens that need it show a brief loading state.
    public private(set) var defaultPolicy: Policy?

    /// The one local `Person` this build treats as "you" — every `NoteBlock`
    /// the user authors from this device attributes to it. Multi-person
    /// identity (voice-enrolled speakers, invited collaborators) isn't built
    /// yet. `nil` until `bootstrap()` completes, same as `defaultPolicy`.
    public private(set) var selfPersonID: PersonID?

    /// Set by `deleteMeeting(_:)` right after a delete succeeds — the one
    /// broadcast every screen holding a *specific* meeting (not a list) can
    /// observe to invalidate itself, since a delete triggered from a sibling
    /// view (Library, Today, Actions) otherwise has no way to reach an
    /// already-open `MeetingDetailView` or iPad's `selectedMeetingID`. Not
    /// cleared after observers react to it — each observer compares against
    /// its own meeting ID, so a stale value is simply never equal again
    /// until the next delete.
    public private(set) var lastDeletedMeetingID: MeetingID?

    /// Bumped whenever content changed somewhere that doesn't have a single
    /// owning screen to refresh directly — right now, just the
    /// post-recording title/calendar prompts, which moved from `TodayView`
    /// to the root views once Today stopped being a permanently mounted tab
    /// (`TodayPromptSheets`' call site in `RootView.swift`/`PadRootView
    /// .swift`). `DashboardView`/`TodayView` observe this and reload.
    public private(set) var contentRevision = 0

    public func bumpContentRevision() {
        contentRevision += 1
    }

    private static let defaultPolicyIDKey = "com.dexterjackson.northstarpromise.defaultPolicyID"
    private static let defaultWorkspaceIDKey = "com.dexterjackson.northstarpromise.defaultWorkspaceID"
    private static let selfPersonIDKey = "com.dexterjackson.northstarpromise.selfPersonID"
    private static let calendarSyncEnabledKey = "com.dexterjackson.northstarpromise.calendarSyncEnabled"
    private static let selectedCalendarIdentifierKey = "com.dexterjackson.northstarpromise.selectedCalendarIdentifier"
    private static let appearanceModeKey = "com.dexterjackson.northstarpromise.appearanceMode"

    public init() throws {
        let (appSupportURL, defaultImportExportDirectoryURL) = try Self.resolveStorageDirectories()
        let appDatabase = try AppDatabase(path: appSupportURL.appendingPathComponent("NorthStar.sqlite").path)

        // Named type in place of a many-member tuple (SwiftLint's
        // `large_tuple` rule caps tuples at 2 — same reasoning
        // `MeetingStateBadge.Appearance` documents).
        let repositories = Self.makeCoreRepositories(appDatabase)
        let clock = SystemClock()

        // Shared between the writer and reader so the write-only and
        // full-access EventKit grants aren't juggled by two independent
        // `EKEventStore` lifecycles talking past each other
        // (`EventKitCalendarEventReader`'s doc comment).
        let calendarEventStore = EKEventStore()
        let scheduledRecordingNotificationScheduler = ScheduledRecordingNotificationScheduler()
        let networkGate = Self.makeNetworkGate(repositories: repositories, clock: clock)
        let deviceID = Self.loadOrCreateDeviceID()

        self.appDatabase = appDatabase
        self.meetingRepository = repositories.meeting
        self.segmentRepository = repositories.segment
        self.timelineEventRepository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)
        self.noteBlockRepository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        self.policyRepository = repositories.policy
        self.workspaceRepository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        self.personRepository = GRDBPersonRepository(dbWriter: appDatabase.dbWriter)
        self.actionRepository = repositories.action
        self.consentRecordRepository = repositories.consentRecord
        self.auditEventRepository = repositories.auditEvent
        self.transcriptTurnRepository = repositories.transcriptTurn
        self.insightRepository = repositories.insight
        self.calendarEventWriter = EventKitCalendarEventWriter(store: calendarEventStore)
        self.calendarEventReader = EventKitCalendarEventReader(store: calendarEventStore)
        self.scheduledRecordingRepository = repositories.scheduledRecording
        (self.projectRepository, self.decisionRepository) = (repositories.project, repositories.decision)
        (self.meetingAttendeeRepository, self.threadRepository) = (repositories.meetingAttendee, repositories.thread)
        (self.threadParticipantRepository, self.projectPersonRepository) = (
            repositories.threadParticipant, repositories.projectPerson
        )
        (self.brainDumpRepository, self.noteRepository) = (repositories.brainDump, repositories.note)
        (self.recurrenceRuleRepository, self.recurrenceExceptionRepository) = (
            repositories.recurrenceRule, repositories.recurrenceException
        )
        self.threadSuggestionDismissalRepository = GRDBThreadSuggestionDismissalRepository(
            dbWriter: appDatabase.dbWriter)
        self.inkAssetFileSystem = LiveInkAssetFileSystem()
        self.networkGate = networkGate
        let ask = Self.makeAskDependencies(appDatabase, repositories: repositories, deviceID: deviceID)
        self.embedder = ask.embedder
        self.embeddingRepository = ask.embeddingRepository
        self.ftsQueryService = ask.ftsQueryService
        self.askAnswerer = ask.askAnswerer
        self.askAuthorizationResolver = ask.askAuthorizationResolver
        let coordinators = Self.makeCoordinators(
            repositories: repositories, ask: ask, clock: clock,
            notificationScheduler: scheduledRecordingNotificationScheduler, networkGate: networkGate)
        self.syncCoordinator = coordinators.sync
        self.intelligenceCoordinator = coordinators.intelligence
        self.scheduledRecordingCoordinator = coordinators.scheduledRecording
        self.featureFlagProvider = ScheduledRecordingEnabledProvider()
        (self.containerRootURL, self.deviceID, self.clock) = (appSupportURL, deviceID, clock)
        self.defaultImportExportDirectoryURL = defaultImportExportDirectoryURL
        self.calendarSyncEnabled = UserDefaults.standard.bool(forKey: Self.calendarSyncEnabledKey)
        self.selectedCalendarIdentifier = UserDefaults.standard.string(forKey: Self.selectedCalendarIdentifierKey)
        self.appearanceMode = Self.loadAppearanceMode()
    }

    /// Updates the published `defaultPolicy` after a caller has already
    /// persisted a change to it (e.g. Settings' "Sync to iCloud" toggle) —
    /// this only refreshes in-memory state for observers, it doesn't write
    /// anything itself.
    public func refreshDefaultPolicy(_ policy: Policy) {
        defaultPolicy = policy
    }

    /// Ensures `defaultPolicy` is set, creating the one local workspace and
    /// its `.localOnly` policy on first launch. Idempotent — safe to call
    /// from every screen's `.task`, not just once at app start.
    public func bootstrap() async throws {
        guard defaultPolicy == nil else { return }

        let defaults = UserDefaults.standard
        let storedPolicyID = defaults.string(forKey: Self.defaultPolicyIDKey).flatMap { UUID(uuidString: $0) }
        let storedPersonID = defaults.string(forKey: Self.selfPersonIDKey).flatMap { UUID(uuidString: $0) }

        var existingPolicy: Policy?
        var existingPerson: Person?
        if let storedPolicyID {
            existingPolicy = try await policyRepository.find(PolicyID(rawValue: storedPolicyID))
        }
        if let storedPersonID {
            existingPerson = try await personRepository.find(PersonID(rawValue: storedPersonID))
        }
        if let existingPolicy, let existingPerson {
            defaultPolicy = existingPolicy
            selfPersonID = existingPerson.personID
            return
        }

        let workspace = Workspace(workspaceID: WorkspaceID(rawValue: UUID()), name: "My Workspace")
        try await workspaceRepository.insert(workspace, at: clock.now())

        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: workspace.workspaceID, defaultProcessingMode: .localOnly)
        try await policyRepository.insert(policy, at: clock.now())

        let person = Person(personID: PersonID(rawValue: UUID()), workspaceID: workspace.workspaceID, name: "You")
        try await personRepository.insert(person, at: clock.now())

        defaults.set(policy.policyID.rawValue.uuidString, forKey: Self.defaultPolicyIDKey)
        defaults.set(workspace.workspaceID.rawValue.uuidString, forKey: Self.defaultWorkspaceIDKey)
        defaults.set(person.personID.rawValue.uuidString, forKey: Self.selfPersonIDKey)
        defaultPolicy = policy
        selfPersonID = person.personID
    }

    /// Builds a fresh `MeetingContainer` and its on-disk directory
    /// structure for `owner` — call once, at Arming, for any of the three
    /// recordable containers (`Meeting`/`BrainDump`/`Note`).
    public func makeContainer(owner: ContentOwnerRef) throws -> MeetingContainer {
        let container = MeetingContainer(appContainerURL: containerRootURL, owner: owner)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())
        return container
    }

    /// `makeContainer(owner:)` convenience for the many existing call sites
    /// that only ever address a real `Meeting`.
    public func makeMeetingContainer(meetingID: MeetingID) throws -> MeetingContainer {
        try makeContainer(owner: .meeting(meetingID))
    }

    /// Deletes a meeting outright: the DB row first (cascades every child
    /// row — segments, notes, transcript, insights, actions, evidence —
    /// per `MeetingRepository.delete`'s doc comment), then its on-disk
    /// directory. DB delete first, disk cleanup second, and disk cleanup
    /// failure is non-fatal (`try?`, same as `CaptureEngine.stop()`'s own
    /// non-fatal `deactivateSession` cleanup) — by the time disk cleanup
    /// runs the meeting is already gone from every list, so a failure there
    /// is an orphaned-file storage leak, not a correctness problem worth
    /// surfacing as "delete failed" when the delete the user asked for
    /// already succeeded.
    public func deleteMeeting(_ meetingID: MeetingID) async throws {
        try await meetingRepository.delete(meetingID)
        try? LiveContainerFileSystem().removeDirectory(
            at: MeetingContainer(appContainerURL: containerRootURL, owner: .meeting(meetingID)).rootURL)
        lastDeletedMeetingID = meetingID
    }

    /// Same shape as `deleteMeeting(_:)` — DB row (`BrainDumpRepository`
    /// explicitly cleans up its owned segments/transcript turns/timeline
    /// events first, same as `MeetingRepository.delete`'s doc comment, since
    /// neither table is a real SQL foreign key any more) then best-effort
    /// disk cleanup.
    public func deleteBrainDump(_ brainDumpID: BrainDumpID) async throws {
        try await brainDumpRepository.delete(brainDumpID)
        try? LiveContainerFileSystem().removeDirectory(
            at: MeetingContainer(appContainerURL: containerRootURL, owner: .brainDump(brainDumpID)).rootURL)
    }

    /// Same shape as `deleteMeeting(_:)` — a `Note` with no recording ever
    /// attached has no on-disk container to clean up, so the best-effort
    /// removal below is simply a no-op for it.
    public func deleteNote(_ noteID: NoteID) async throws {
        try await noteRepository.delete(noteID)
        try? LiveContainerFileSystem().removeDirectory(
            at: MeetingContainer(appContainerURL: containerRootURL, owner: .note(noteID)).rootURL)
    }

    /// Composes the Dashboard's single shared view model
    /// (`DashboardComposer`'s own doc comment: reads already-persisted
    /// data, never calls the network/embedder/an LLM). Both iPhone and
    /// iPad Dashboard screens call this same method so the two builds
    /// render pure functions of one model, per `DASHBOARD_SPEC.md` §6.
    public func composeDashboard() async throws -> DashboardModel? {
        guard let workspaceID = defaultPolicy?.workspaceID else { return nil }
        let repositories = DashboardRepositories(
            meeting: meetingRepository, action: actionRepository, decision: decisionRepository, thread: threadRepository
        )
        return try await DashboardComposer.compose(workspaceID: workspaceID, repositories: repositories, clock: clock)
    }

    /// One `RelationshipRepositories` bundle every "everything tied to X"
    /// caller shares — `RelationshipGraph`'s own doc comment ("The Spine",
    /// 2026-08-22).
    public func composeWeeklyBrief() async throws -> WeeklyBrief? {
        guard let workspaceID = defaultPolicy?.workspaceID else { return nil }
        let repositories = WeeklyBriefRepositories(
            meeting: meetingRepository, action: actionRepository, decision: decisionRepository,
            thread: threadRepository, person: personRepository)
        return try await WeeklyBriefComposer.compose(workspaceID: workspaceID, repositories: repositories, clock: clock)
    }

    public var relationshipRepositories: RelationshipRepositories {
        RelationshipRepositories(
            meeting: meetingRepository, action: actionRepository, decision: decisionRepository,
            thread: threadRepository, project: projectRepository, meetingAttendee: meetingAttendeeRepository,
            threadParticipant: threadParticipantRepository, projectPerson: projectPersonRepository)
    }

    /// Builds a `CaptureEngine` wired to real capture (`AVAudioEngine`),
    /// real encoding (`AVAudioFile`/AAC), and real durable storage for one
    /// recording session — a `Meeting`, a `BrainDump`, or a `Note` that just
    /// had a recording attached. A fresh instance per session —
    /// `CaptureEngine` and `Segmenter` are both single-session actors, not
    /// singletons.
    public func makeCaptureEngine(owner: ContentOwnerRef, container: MeetingContainer) -> CaptureEngine {
        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let segmentRepository = segmentRepository
        let timelineEventRepository = timelineEventRepository
        let clock = clock
        let deviceID = deviceID

        return CaptureEngine(backend: AVAudioEngineCaptureBackend()) { format in
            Segmenter(
                container: container, audioEncoder: AVAudioFileSegmentEncoder(),
                segmentFileSystem: LiveSegmentFileSystem(), manifestWriter: manifestWriter,
                segmentRepository: segmentRepository, timelineEventRepository: timelineEventRepository, clock: clock,
                owner: owner, deviceID: deviceID, audioFormat: format)
        }
    }

}

/// `AllFlagsOffProvider` plus one exception — the user has explicitly
/// directed Scheduled Recording into daily use in Today (docs/07 §2.1),
/// ahead of a real remote-config/build-setting-backed provider existing.
/// Flipping this does not resolve `NSP-149`'s two open hardware-validation
/// risks (EventKit full-access/write-only grant interaction; whether a
/// live recording and its auto-stop timer survive backgrounding without
/// `UIBackgroundModes: audio` declared) — those stay real, open risks,
/// this only makes the feature reachable. `AllFlagsOffProvider` itself is
/// untouched, so anything else relying on "every flag off" keeps working.
private struct ScheduledRecordingEnabledProvider: FeatureFlagProviding {
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        flag == .scheduledRecording
    }
}
