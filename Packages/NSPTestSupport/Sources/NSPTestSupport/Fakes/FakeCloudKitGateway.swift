import CloudKit
import NSPSync

/// In-memory `CloudKitGateway` so tests never touch a real `CKContainer`
/// (docs/11 §4, NSP-034). Records every call it receives, in order, so a
/// test can assert not just the outcome but that a `.localOnly` meeting
/// never reached this fake at all.
public actor FakeCloudKitGateway: CloudKitGateway {
    public enum Call: Sendable, Equatable {
        case fetchOrCreateZone(CKRecordZone.ID)
        case save([CKRecord.ID])
        case delete([CKRecord.ID])
    }

    public private(set) var calls: [Call] = []
    private var zones: [CKRecordZone.ID: CKRecordZone] = [:]
    private var records: [CKRecord.ID: CKRecord] = [:]

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
}
