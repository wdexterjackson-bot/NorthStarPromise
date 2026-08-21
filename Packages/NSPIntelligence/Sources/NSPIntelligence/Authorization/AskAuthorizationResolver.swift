import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy

public enum AskAuthorizationError: Error, Sendable, Hashable {
    /// `.series`/`.projectOrTag` have no backing data model — no
    /// `series`/`tag` column exists anywhere in the schema. Thrown rather
    /// than silently resolving to an empty set, so a caller can't mistake
    /// "not supported" for "found nothing."
    case scopeNotYetSupported(reason: String)
}

/// Turns an `AskScope` into a concrete, authorized `Set<MeetingID>` — the
/// I/O half of Ask's authorization-before-retrieval hard rule (docs/04
/// §10.2). Lives in `NSPIntelligence`, not `NSPPolicy`, because resolving a
/// scope needs `MeetingRepository` (GRDB I/O), and `NSPPolicy` is
/// deliberately I/O-free (`PolicyAuthority`'s own doc comment). Every case
/// filters through `AskAuthorizationPolicy.isEligible` — the pure predicate
/// — so this type carries no authorization *logic* of its own, only the
/// fetching.
public struct AskAuthorizationResolver: Sendable {
    private let meetingRepository: any MeetingRepository
    private let projectRepository: any ProjectRepository
    private let currentDeviceID: DeviceID

    public init(
        meetingRepository: any MeetingRepository, projectRepository: any ProjectRepository, currentDeviceID: DeviceID
    ) {
        self.meetingRepository = meetingRepository
        self.projectRepository = projectRepository
        self.currentDeviceID = currentDeviceID
    }

    public func resolve(_ scope: AskScope, currentWorkspaceID: WorkspaceID) async throws -> Set<MeetingID> {
        switch scope {
        case .meeting(let meetingID):
            return try await Self.eligibleSet(from: [meetingID], repository: meetingRepository, device: currentDeviceID)

        case .selectedMeetings(let meetingIDs):
            return try await Self.eligibleSet(
                from: Array(meetingIDs), repository: meetingRepository, device: currentDeviceID)

        case .workspace:
            let meetings = try await meetingRepository.fetchAll(workspaceID: currentWorkspaceID, includeDeleted: false)
            return Set(
                meetings.filter { AskAuthorizationPolicy.isEligible(meeting: $0, currentDeviceID: currentDeviceID) }
                    .map(\.meetingID))

        case .dateRange(let range):
            let meetings = try await meetingRepository.fetchAll(workspaceID: currentWorkspaceID, includeDeleted: false)
            return Set(
                meetings.filter {
                    AskAuthorizationPolicy.isEligible(meeting: $0, currentDeviceID: currentDeviceID)
                        && range.contains($0.startedAt)
                }.map(\.meetingID))

        case .series:
            throw AskAuthorizationError.scopeNotYetSupported(
                reason: "No 'series' column exists in the schema yet — meetings aren't grouped into series.")

        case .projectOrTag(let rawProjectID):
            guard let projectUUID = UUID(uuidString: rawProjectID) else {
                throw AskAuthorizationError.scopeNotYetSupported(reason: "'\(rawProjectID)' isn't a valid project ID.")
            }
            let meetingIDs = try await projectRepository.fetchMeetingIDs(for: ProjectID(rawValue: projectUUID))
            return try await Self.eligibleSet(
                from: Array(meetingIDs), repository: meetingRepository, device: currentDeviceID)
        }
    }

    private static func eligibleSet(
        from meetingIDs: [MeetingID], repository: any MeetingRepository, device: DeviceID
    ) async throws -> Set<MeetingID> {
        var result: Set<MeetingID> = []
        for meetingID in meetingIDs {
            guard let meeting = try await repository.find(meetingID) else { continue }
            if AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: device) {
                result.insert(meetingID)
            }
        }
        return result
    }
}
