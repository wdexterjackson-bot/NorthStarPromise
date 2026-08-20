import CloudKit

/// Where `ZoneSyncEngine` persists the per-zone `SyncCursor` between fetch
/// calls (docs/02 §6: "Change tokens per zone; incremental fetch").
/// Protocol-injected so tests never touch real disk (docs/11 §4).
///
/// `InMemoryChangeTokenStore` is the only implementation today — a cursor
/// that doesn't survive app relaunch just means the next sync re-fetches
/// from the start of the zone (correct, if wasteful), never a correctness
/// problem. A durable, file-backed store is a reasonable follow-up ticket,
/// not something this one's acceptance requires.
public protocol ChangeTokenStore: Sendable {
    func cursor(for zoneID: CKRecordZone.ID) async -> SyncCursor?
    func setCursor(_ cursor: SyncCursor?, for zoneID: CKRecordZone.ID) async
}

public actor InMemoryChangeTokenStore: ChangeTokenStore {
    private var cursors: [CKRecordZone.ID: SyncCursor] = [:]

    public init() {}

    public func cursor(for zoneID: CKRecordZone.ID) async -> SyncCursor? {
        cursors[zoneID]
    }

    public func setCursor(_ cursor: SyncCursor?, for zoneID: CKRecordZone.ID) async {
        cursors[zoneID] = cursor
    }
}
