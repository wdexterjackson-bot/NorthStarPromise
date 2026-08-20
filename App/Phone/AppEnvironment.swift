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
    public let inkAssetFileSystem: any InkAssetFileSystem
    /// The single I5 choke point (docs/06 §2) — every `NSPSync` write
    /// already calls this internally; `syncCoordinator` below is the only
    /// thing in `App/Phone` that needs it directly.
    public let networkGate: any NetworkGate
    public let syncCoordinator: AppSyncCoordinator
    public let intelligenceCoordinator: IntelligenceCoordinator

    public let containerRootURL: URL
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

    private static let defaultPolicyIDKey = "com.dexterjackson.northstarpromise.defaultPolicyID"
    private static let defaultWorkspaceIDKey = "com.dexterjackson.northstarpromise.defaultWorkspaceID"
    private static let selfPersonIDKey = "com.dexterjackson.northstarpromise.selfPersonID"
    private static let calendarSyncEnabledKey = "com.dexterjackson.northstarpromise.calendarSyncEnabled"
    private static let selectedCalendarIdentifierKey = "com.dexterjackson.northstarpromise.selectedCalendarIdentifier"

    public init() throws {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dbURL = appSupportURL.appendingPathComponent("NorthStar.sqlite")
        let appDatabase = try AppDatabase(path: dbURL.path)

        let meetingRepository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        let segmentRepository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        let policyRepository = GRDBPolicyRepository(dbWriter: appDatabase.dbWriter)
        let consentRecordRepository = GRDBConsentRecordRepository(dbWriter: appDatabase.dbWriter)
        let auditEventRepository = GRDBAuditEventRepository(dbWriter: appDatabase.dbWriter)
        let transcriptTurnRepository = GRDBTranscriptTurnRepository(dbWriter: appDatabase.dbWriter)
        let insightRepository = GRDBInsightRepository(dbWriter: appDatabase.dbWriter)
        let actionRepository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        let clock = SystemClock()

        let networkGate = DefaultNetworkGate(
            auditRecorder: PersistedAuditEventRecorder(repository: auditEventRepository, clock: clock),
            consentLookup: PersistedConsentRecordLookup(repository: consentRecordRepository),
            policyLookup: PersistedPolicySnapshotLookup(
                meetingRepository: meetingRepository, policyRepository: policyRepository))

        self.appDatabase = appDatabase
        self.meetingRepository = meetingRepository
        self.segmentRepository = segmentRepository
        self.timelineEventRepository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)
        self.noteBlockRepository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        self.policyRepository = policyRepository
        self.workspaceRepository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        self.personRepository = GRDBPersonRepository(dbWriter: appDatabase.dbWriter)
        self.actionRepository = actionRepository
        self.consentRecordRepository = consentRecordRepository
        self.auditEventRepository = auditEventRepository
        self.transcriptTurnRepository = transcriptTurnRepository
        self.insightRepository = insightRepository
        self.calendarEventWriter = EventKitCalendarEventWriter()
        self.inkAssetFileSystem = LiveInkAssetFileSystem()
        self.networkGate = networkGate
        self.syncCoordinator = AppSyncCoordinator(
            networkGate: networkGate, meetingRepository: meetingRepository, segmentRepository: segmentRepository)
        self.intelligenceCoordinator = IntelligenceCoordinator(
            segmentRepository: segmentRepository, transcriptTurnRepository: transcriptTurnRepository,
            insightRepository: insightRepository, actionRepository: actionRepository,
            meetingRepository: meetingRepository, clock: clock)
        self.containerRootURL = appSupportURL
        self.deviceID = Self.loadOrCreateDeviceID()
        self.clock = clock
        self.calendarSyncEnabled = UserDefaults.standard.bool(forKey: Self.calendarSyncEnabledKey)
        self.selectedCalendarIdentifier = UserDefaults.standard.string(forKey: Self.selectedCalendarIdentifierKey)
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
    /// structure for `meetingID` — call once, at Arming.
    public func makeMeetingContainer(meetingID: MeetingID) throws -> MeetingContainer {
        let container = MeetingContainer(appContainerURL: containerRootURL, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())
        return container
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
        let container = MeetingContainer(appContainerURL: containerRootURL, meetingID: meetingID)
        try? LiveContainerFileSystem().removeDirectory(at: container.rootURL)
    }

    /// Builds a `CaptureEngine` wired to real capture (`AVAudioEngine`),
    /// real encoding (`AVAudioFile`/AAC), and real durable storage for one
    /// meeting. A fresh instance per recording session — `CaptureEngine`
    /// and `Segmenter` are both single-session actors, not singletons.
    public func makeCaptureEngine(meetingID: MeetingID, container: MeetingContainer) -> CaptureEngine {
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
                meetingID: meetingID, deviceID: deviceID, audioFormat: format)
        }
    }

    private static func loadOrCreateDeviceID() -> DeviceID {
        let key = "com.dexterjackson.northstarpromise.deviceID"
        if let stored = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return DeviceID(rawValue: uuid)
        }
        let fresh = DeviceID(rawValue: UUID())
        UserDefaults.standard.set(fresh.rawValue.uuidString, forKey: key)
        return fresh
    }
}
