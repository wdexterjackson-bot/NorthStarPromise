import CloudKit
import Foundation
import NSPSync

/// In-memory `CloudKitGateway` so tests never touch a real `CKContainer`
/// (docs/11 §4, NSP-034). Records every call it receives, in order, so a
/// test can assert not just the outcome but that a `.localOnly` meeting
/// never reached this fake at all.
///
/// `fetchChanges` is scripted rather than derived from `save`/`delete`
/// history: queue pages with `enqueueChangePage`, and each `fetchChanges`
/// call dequeues the next one (or returns an empty, `moreComing: false`
/// page once the queue is drained). `SyncCursor` values here are opaque
/// test fixtures — an incrementing counter, not a real archived
/// `CKServerChangeToken` — since `FakeCloudKitGateway` never has a genuine
/// token to synthesize one from (docs/11 §4; see `SyncCursor`'s own doc
/// comment for why `LiveCloudKitGateway` is the only place that matters).
public actor FakeCloudKitGateway: CloudKitGateway {
    public enum Call: Sendable, Equatable {
        case fetchOrCreateZone(CKRecordZone.ID)
        case save([CKRecord.ID])
        case delete([CKRecord.ID])
        case fetchChanges(SyncCursor?)
    }

    public private(set) var calls: [Call] = []
    private var zones: [CKRecordZone.ID: CKRecordZone] = [:]
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var queuedPages: [ZoneChanges] = []
    private var cursorCounter = 0

    public init() {}

    public func fetchOrCreateZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        calls.append(.fetchOrCreateZone(zoneID))
        if let existing = zones[zoneID] { return existing }
        let zone = CKRecordZone(zoneID: zoneID)
        zones[zoneID] = zone
        return zone
    }

    public func save(_ records: [CKRecord]) async throws -> [CKRecord] {
        calls.append(.save(records.map(\.recordID)))
        for record in records {
            self.records[record.recordID] = record
        }
        return records
    }

    public func delete(_ recordIDs: [CKRecord.ID]) async throws {
        calls.append(.delete(recordIDs))
        for recordID in recordIDs {
            records[recordID] = nil
        }
    }

    public func record(for recordID: CKRecord.ID) -> CKRecord? {
        records[recordID]
    }

    /// A fresh, unique fixture cursor — for building `ZoneChanges` pages to
    /// enqueue, or for asserting what a caller passed as `since:`.
    public func makeCursor() -> SyncCursor {
        cursorCounter += 1
        return SyncCursor(data: Data("fixture-cursor-\(cursorCounter)".utf8))
    }

    public func enqueueChangePage(_ page: ZoneChanges) {
        queuedPages.append(page)
    }

    public func fetchChanges(in zoneID: CKRecordZone.ID, since cursor: SyncCursor?) async throws -> ZoneChanges {
        calls.append(.fetchChanges(cursor))
        guard !queuedPages.isEmpty else {
            return ZoneChanges(
                changedRecords: [], deletedRecordIDs: [], cursor: cursor ?? makeCursor(), moreComing: false)
        }
        return queuedPages.removeFirst()
    }
}
