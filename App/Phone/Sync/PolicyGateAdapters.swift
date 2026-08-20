import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy

/// The three real collaborators `DefaultNetworkGate` needs. `NSPPolicy`
/// has no I/O dependency by design (`CLAUDE.md` §3's dependency graph), so
/// it only declares these protocols; `App/Phone` is the composition root
/// that supplies adapters backed by real `NSPPersistence` repositories —
/// exactly the role each protocol's own doc comment says belongs outside
/// `NSPPolicy`.
struct PersistedAuditEventRecorder: AuditEventRecorder {
    let repository: any AuditEventRepository
    let clock: any Clock

    func record(_ event: AuditEvent) async throws {
        try await repository.insert(event, at: clock.now())
    }
}

struct PersistedConsentRecordLookup: ConsentRecordLookup {
    let repository: any ConsentRecordRepository

    func hasConsentRecord(for meetingID: MeetingID) async -> Bool {
        (try? await repository.hasRecord(forMeetingID: meetingID)) ?? false
    }
}

/// Resolves a meeting's frozen `Policy` snapshot via its `policyID` — two
/// repository reads, both already real and wired into `AppEnvironment`.
struct PersistedPolicySnapshotLookup: PolicySnapshotLookup {
    let meetingRepository: any MeetingRepository
    let policyRepository: any PolicyRepository

    func policy(for meetingID: MeetingID) async -> Policy? {
        guard let meeting = try? await meetingRepository.find(meetingID) else { return nil }
        return try? await policyRepository.find(meeting.policyID)
    }
}
