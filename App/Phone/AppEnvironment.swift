import Foundation
import NSPActions
import NSPCore
import NSPMedia
import NSPPersistence
import Observation

/// The app's composition root — construction and wiring only, no
/// business logic (`CLAUDE.md` §3: "app targets contain no business
/// logic"). Every screen reads its dependencies from this one place
/// rather than constructing its own database connection or repository.
///
/// `NetworkGate` isn't wired here yet: nothing in this pass calls it —
/// recording is purely local (I1/I2 concerns), and CloudKit sync isn't
/// connected to any screen yet. Wiring it in is a fast follow, not a
/// deferred requirement of anything built so far.
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
    public let calendarEventWriter: any CalendarEventWriter

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

        self.appDatabase = appDatabase
        self.meetingRepository = GRDBMeetingRepository(dbWriter: appDatabase.dbWriter)
        self.segmentRepository = GRDBSegmentRepository(dbWriter: appDatabase.dbWriter)
        self.timelineEventRepository = GRDBTimelineEventRepository(dbWriter: appDatabase.dbWriter)
        self.noteBlockRepository = GRDBNoteBlockRepository(dbWriter: appDatabase.dbWriter)
        self.policyRepository = GRDBPolicyRepository(dbWriter: appDatabase.dbWriter)
        self.workspaceRepository = GRDBWorkspaceRepository(dbWriter: appDatabase.dbWriter)
        self.personRepository = GRDBPersonRepository(dbWriter: appDatabase.dbWriter)
        self.actionRepository = GRDBActionRepository(dbWriter: appDatabase.dbWriter)
        self.calendarEventWriter = EventKitCalendarEventWriter()
        self.containerRootURL = appSupportURL
        self.deviceID = Self.loadOrCreateDeviceID()
        self.clock = SystemClock()
        self.calendarSyncEnabled = UserDefaults.standard.bool(forKey: Self.calendarSyncEnabledKey)
        self.selectedCalendarIdentifier = UserDefaults.standard.string(forKey: Self.selectedCalendarIdentifierKey)
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
