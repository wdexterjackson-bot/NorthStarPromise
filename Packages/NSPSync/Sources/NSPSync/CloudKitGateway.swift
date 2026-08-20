import CloudKit

/// Abstracts exactly the CloudKit operations `CloudKitSyncCoordinator`
/// needs, protocol-injected so tests never touch a real `CKContainer`
/// (docs/11 §4). Scoped to zone bootstrap and record save/delete — the
/// change-token incremental fetch loop is NSP-036, and `CKAsset`
/// content-addressed dedupe is NSP-035.
public protocol CloudKitGateway: Sendable {
    func fetchOrCreateZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone
    func save(_ records: [CKRecord]) async throws -> [CKRecord]
    func delete(_ recordIDs: [CKRecord.ID]) async throws
}

/// The real private database, backed by `CKContainer.default()`.
public struct LiveCloudKitGateway: CloudKitGateway {
    private let database: CKDatabase

    public init(container: CKContainer = .default()) {
        self.database = container.privateCloudDatabase
    }

    public func fetchOrCreateZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        do {
            return try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            return try await database.save(CKRecordZone(zoneID: zoneID))
        }
    }

    public func save(_ records: [CKRecord]) async throws -> [CKRecord] {
        let result = try await database.modifyRecords(saving: records, deleting: [])
        return try result.saveResults.values.map { try $0.get() }
    }

    public func delete(_ recordIDs: [CKRecord.ID]) async throws {
        _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
    }
}
