import Foundation
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

    public let containerRootURL: URL
    public let deviceID: DeviceID
    public let clock: any Clock

    /// The one local workspace/policy this build creates on first launch
    /// (docs/06 §1.1's safest default: `.localOnly`). Multi-workspace
    /// creation/switching UI doesn't exist yet — every meeting Arms
    /// against this policy until it does. `nil` until `bootstrap()`
    /// completes; screens that need it show a brief loading state.
    public private(set) var defaultPolicy: Policy?

    private static let defaultPolicyIDKey = "com.dexterjackson.northstarpromise.defaultPolicyID"
    private static let defaultWorkspaceIDKey = "com.dexterjackson.northstarpromise.defaultWorkspaceID"

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
        self.containerRootURL = appSupportURL
        self.deviceID = Self.loadOrCreateDeviceID()
        self.clock = SystemClock()
    }

    /// Ensures `defaultPolicy` is set, creating the one local workspace and
    /// its `.localOnly` policy on first launch. Idempotent — safe to call
    /// from every screen's `.task`, not just once at app start.
    public func bootstrap() async throws {
        guard defaultPolicy == nil else { return }

        let defaults = UserDefaults.standard
        let storedPolicyID = defaults.string(forKey: Self.defaultPolicyIDKey).flatMap { UUID(uuidString: $0) }
        if let storedPolicyID, let existing = try await policyRepository.find(PolicyID(rawValue: storedPolicyID)) {
            defaultPolicy = existing
            return
        }

        let workspace = Workspace(workspaceID: WorkspaceID(rawValue: UUID()), name: "My Workspace")
        try await workspaceRepository.insert(workspace, at: clock.now())

        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: workspace.workspaceID, defaultProcessingMode: .localOnly)
        try await policyRepository.insert(policy, at: clock.now())

        defaults.set(policy.policyID.rawValue.uuidString, forKey: Self.defaultPolicyIDKey)
        defaults.set(workspace.workspaceID.rawValue.uuidString, forKey: Self.defaultWorkspaceIDKey)
        defaultPolicy = policy
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
