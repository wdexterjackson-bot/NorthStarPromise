import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPIntelligence

/// A local, in-memory `MeetingRepository` — `NSPIntelligenceTests` can't
/// depend on `NSPTestSupport`'s shared `FakeMeetingRepository` since
/// `NSPTestSupport` itself depends on `NSPIntelligence` (the reverse
/// direction would be circular).
private actor FakeMeetingRepository: MeetingRepository {
    private var storage: [MeetingID: Meeting] = [:]

    func seed(_ meetings: [Meeting]) {
        for meeting in meetings { storage[meeting.meetingID] = meeting }
    }

    func insert(_ meeting: Meeting, at date: Date) async throws { storage[meeting.meetingID] = meeting }
    func update(_ meeting: Meeting, at date: Date) async throws { storage[meeting.meetingID] = meeting }
    func find(_ id: MeetingID) async throws -> Meeting? { storage[id] }
    func delete(_ id: MeetingID) async throws { storage.removeValue(forKey: id) }
    func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Meeting] {
        storage.values.filter { $0.workspaceID == workspaceID && (includeDeleted || $0.deletedAt == nil) }
    }
    func fetchAll(threadID: NSPThreadID) async throws -> [Meeting] { [] }
}

/// A local, in-memory `ProjectRepository` — same circular-dependency
/// reasoning as `FakeMeetingRepository` above. Only `fetchMeetingIDs` is
/// exercised by these tests; the rest are trivial stubs to satisfy the
/// protocol.
private actor FakeProjectRepository: ProjectRepository {
    private var meetingsByProject: [ProjectID: Set<MeetingID>] = [:]

    func seed(_ projectID: ProjectID, meetingIDs: Set<MeetingID>) {
        meetingsByProject[projectID] = meetingIDs
    }

    func insert(_ project: Project, at date: Date) async throws {}
    func update(_ project: Project, at date: Date) async throws {}
    func find(_ id: ProjectID) async throws -> Project? { nil }
    func fetchAll(workspaceID: WorkspaceID) async throws -> [Project] { [] }
    func delete(_ id: ProjectID) async throws {}
    func setProjects(for meetingID: MeetingID, projectIDs: Set<ProjectID>) async throws {}
    func fetchProjectIDs(for meetingID: MeetingID) async throws -> Set<ProjectID> { [] }
    func fetchMeetingIDs(for projectID: ProjectID) async throws -> Set<MeetingID> {
        meetingsByProject[projectID] ?? []
    }
}

@Suite("AskAuthorizationResolver")
struct AskAuthorizationResolverTests {
    private static let thisDevice = DeviceID(rawValue: UUID())
    private static let workspaceID = WorkspaceID(rawValue: UUID())

    private static func makeMeeting(
        id: MeetingID = MeetingID(rawValue: UUID()), excludedFromMemory: Bool = false,
        processingMode: ProcessingMode = .cloudAllowed, startedAt: Date = Date()
    ) -> Meeting {
        Meeting(
            meetingID: id, workspaceID: Self.workspaceID, title: "Test", captureMode: .phone,
            originDeviceID: Self.thisDevice, startedAt: startedAt, lifecycleState: .ready,
            policyID: PolicyID(rawValue: UUID()), processingMode: processingMode, availability: .complete,
            excludedFromMemory: excludedFromMemory, createdAt: startedAt, updatedAt: startedAt)
    }

    @Test func test_meetingScope_resolvesToJustThatMeetingWhenEligible() async throws {
        let repository = FakeMeetingRepository()
        let meeting = Self.makeMeeting()
        await repository.seed([meeting, Self.makeMeeting()])
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)

        let result = try await resolver.resolve(.meeting(meeting.meetingID), currentWorkspaceID: Self.workspaceID)

        #expect(result == [meeting.meetingID])
    }

    @Test func test_meetingScope_excludedFromMemory_resolvesToEmpty() async throws {
        let repository = FakeMeetingRepository()
        let meeting = Self.makeMeeting(excludedFromMemory: true)
        await repository.seed([meeting])
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)

        let result = try await resolver.resolve(.meeting(meeting.meetingID), currentWorkspaceID: Self.workspaceID)

        #expect(result.isEmpty)
    }

    @Test func test_workspaceScope_returnsOnlyEligibleMeetingsInThatWorkspace() async throws {
        let repository = FakeMeetingRepository()
        let eligible = Self.makeMeeting()
        let excluded = Self.makeMeeting(excludedFromMemory: true)
        let otherWorkspace = Self.makeMeeting(id: MeetingID(rawValue: UUID()))
        await repository.seed([eligible, excluded])
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)

        let result = try await resolver.resolve(.workspace(Self.workspaceID), currentWorkspaceID: Self.workspaceID)

        #expect(result == [eligible.meetingID])
    }

    @Test func test_dateRangeScope_filtersToMeetingsStartingWithinRange() async throws {
        let repository = FakeMeetingRepository()
        let inRange = Self.makeMeeting(startedAt: Date(timeIntervalSince1970: 1_000_000))
        let outOfRange = Self.makeMeeting(startedAt: Date(timeIntervalSince1970: 5_000_000))
        await repository.seed([inRange, outOfRange])
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)
        let range = Date(timeIntervalSince1970: 900_000)...Date(timeIntervalSince1970: 1_100_000)

        let result = try await resolver.resolve(.dateRange(range), currentWorkspaceID: Self.workspaceID)

        #expect(result == [inRange.meetingID])
    }

    @Test func test_selectedMeetingsScope_filtersOutIneligibleOnes() async throws {
        let repository = FakeMeetingRepository()
        let eligible = Self.makeMeeting()
        let excluded = Self.makeMeeting(excludedFromMemory: true)
        await repository.seed([eligible, excluded])
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)

        let result = try await resolver.resolve(
            .selectedMeetings([eligible.meetingID, excluded.meetingID]), currentWorkspaceID: Self.workspaceID)

        #expect(result == [eligible.meetingID])
    }

    @Test func test_seriesScope_throwsScopeNotYetSupported() async throws {
        let repository = FakeMeetingRepository()
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(), currentDeviceID: Self.thisDevice)

        await #expect(throws: AskAuthorizationError.self) {
            try await resolver.resolve(.series("standup"), currentWorkspaceID: Self.workspaceID)
        }
    }

    @Test func test_projectOrTagScope_resolvesToEligibleMeetingsInThatProject() async throws {
        let meetingRepository = FakeMeetingRepository()
        let projectRepository = FakeProjectRepository()
        let eligible = Self.makeMeeting()
        let excluded = Self.makeMeeting(excludedFromMemory: true)
        let notInProject = Self.makeMeeting()
        await meetingRepository.seed([eligible, excluded, notInProject])
        let projectID = ProjectID(rawValue: UUID())
        await projectRepository.seed(projectID, meetingIDs: [eligible.meetingID, excluded.meetingID])
        let resolver = AskAuthorizationResolver(
            meetingRepository: meetingRepository, projectRepository: projectRepository,
            currentDeviceID: Self.thisDevice)

        let result = try await resolver.resolve(
            .projectOrTag(projectID.rawValue.uuidString), currentWorkspaceID: Self.workspaceID)

        #expect(result == [eligible.meetingID])
    }

    @Test func test_projectOrTagScope_invalidID_throwsScopeNotYetSupported() async throws {
        let repository = FakeMeetingRepository()
        let resolver = AskAuthorizationResolver(
            meetingRepository: repository, projectRepository: FakeProjectRepository(),
            currentDeviceID: Self.thisDevice)

        await #expect(throws: AskAuthorizationError.self) {
            try await resolver.resolve(.projectOrTag("not-a-uuid"), currentWorkspaceID: Self.workspaceID)
        }
    }
}
