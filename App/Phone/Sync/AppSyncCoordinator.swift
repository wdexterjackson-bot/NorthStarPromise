import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy
import NSPSync
import Observation

/// Where the last `syncNow()` call landed. `.failed` is an expected,
/// honest outcome until this app's CloudKit entitlements/container are
/// actually provisioned (see `docs/09-BACKLOG.md`'s sync status note) —
/// `LiveCloudKitGateway` is real and wired, it just has nowhere to connect
/// to yet.
public enum SyncStatus: Equatable {
    case idle
    case syncing
    case succeeded(Date)
    case failed(String)
}

/// Thin App-layer orchestrator over `NSPSync`'s per-record primitives —
/// same shape as `RecordingSession`: no business logic of its own, just
/// composition and a loop, since `CloudKitSyncCoordinator`/`ZoneSyncEngine`
/// expose no "sync everything now" entry point themselves.
///
/// **`CKContainer.default()` crashes, it doesn't throw**, when no
/// `com.apple.developer.icloud-container-identifiers` entitlement is
/// configured (an uncaught Objective-C `CKException`, not a catchable
/// Swift `Error`) — true of this build today (`docs/09-BACKLOG.md`'s sync
/// status note: no Apple Developer Team/entitlements/container are wired
/// up yet). So this type never constructs `LiveCloudKitGateway` (or
/// anything built on it) until `FileManager
/// .url(forUbiquityContainerIdentifier:)` — which returns `nil` instead
/// of crashing when iCloud isn't configured — confirms it's safe to.
@MainActor
@Observable
public final class AppSyncCoordinator {
    public private(set) var status: SyncStatus = .idle

    private let networkGate: any NetworkGate
    private let meetingRepository: any MeetingRepository
    private let segmentRepository: any SegmentRepository
    private var cloudKit: CloudKitPieces?

    private struct CloudKitPieces {
        let coordinator: CloudKitSyncCoordinator
        let zoneSyncEngine: ZoneSyncEngine
        let assetUploader: CKAssetUploader
    }

    public init(
        networkGate: any NetworkGate, meetingRepository: any MeetingRepository,
        segmentRepository: any SegmentRepository
    ) {
        self.networkGate = networkGate
        self.meetingRepository = meetingRepository
        self.segmentRepository = segmentRepository
    }

    /// `true` only once this device has iCloud configured at all — checked
    /// with an API that returns `nil` rather than crashing when it isn't
    /// (see the type doc comment). Doesn't guarantee this *app's* CloudKit
    /// container is provisioned, just that it's safe to find out.
    private static func isCloudKitReachable() -> Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    private func cloudKitPieces() -> CloudKitPieces? {
        if let cloudKit { return cloudKit }
        guard Self.isCloudKitReachable() else { return nil }
        let gateway = LiveCloudKitGateway()
        let pieces = CloudKitPieces(
            coordinator: CloudKitSyncCoordinator(networkGate: networkGate, gateway: gateway),
            zoneSyncEngine: ZoneSyncEngine(
                gateway: gateway, tokenStore: InMemoryChangeTokenStore(), meetingRepository: meetingRepository,
                segmentRepository: segmentRepository),
            assetUploader: CKAssetUploader(
                networkGate: networkGate, gateway: gateway, segmentRepository: segmentRepository))
        cloudKit = pieces
        return pieces
    }

    /// Pushes every meeting/segment in the workspace, then pulls whatever
    /// changed remotely. `.localOnly` meetings throw `SyncError
    /// .egressDenied` from `syncMeeting` — expected, per `NSPSync`'s own
    /// gating (its test suite proves the gateway is never touched for
    /// one) — so each meeting's failure is swallowed without aborting the
    /// rest of the loop.
    public func syncNow(workspaceID: WorkspaceID) async {
        status = .syncing
        guard let pieces = cloudKitPieces() else {
            status = .failed("iCloud isn't available on this device/build yet.")
            return
        }
        do {
            let meetings = try await meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
            guard let first = meetings.first else {
                status = .succeeded(Date())
                return
            }
            let zone = try await pieces.coordinator.bootstrapZone(for: first)

            for meeting in meetings {
                _ = try? await pieces.coordinator.syncMeeting(meeting)
                let segments = try await segmentRepository.fetchAll(owner: .meeting(meeting.meetingID))
                for segment in segments {
                    _ = try? await pieces.assetUploader.upload(segment, meeting: meeting)
                }
            }

            _ = try await pieces.zoneSyncEngine.syncZone(zone.zoneID)
            status = .succeeded(Date())
        } catch {
            status = .failed("\(error)")
        }
    }
}
