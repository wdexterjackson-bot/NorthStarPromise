import CloudKit
import Foundation

/// An opaque, archived `CKServerChangeToken` (docs/02 §6, NSP-036).
///
/// `CKServerChangeToken` itself has no public initializer — it's
/// server-issued only (`init()` is `NS_UNAVAILABLE`) — so it can't cross a
/// protocol boundary a fake needs to satisfy: a test double has no way to
/// mint one. `SyncCursor` wraps the token's own `NSSecureCoding` archive as
/// plain `Data` instead, which is trivial for a fake to synthesize and
/// trivial to persist durably later. Only `LiveCloudKitGateway` ever
/// interprets the bytes as a real token.
public struct SyncCursor: Sendable, Hashable, Codable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// One page of `fetchChanges` (docs/02 §6 "Change tokens per zone;
/// incremental fetch"; NSP-036). `moreComing` mirrors
/// `CKDatabase.RecordZoneChange`'s own paging signal — a caller loops,
/// feeding `cursor` back in, until it's `false`.
public struct ZoneChanges: Sendable {
    public let changedRecords: [CKRecord]
    public let deletedRecordIDs: [CKRecord.ID]
    public let cursor: SyncCursor
    public let moreComing: Bool

    public init(changedRecords: [CKRecord], deletedRecordIDs: [CKRecord.ID], cursor: SyncCursor, moreComing: Bool) {
        self.changedRecords = changedRecords
        self.deletedRecordIDs = deletedRecordIDs
        self.cursor = cursor
        self.moreComing = moreComing
    }
}

/// Abstracts exactly the CloudKit operations `CloudKitSyncCoordinator` and
/// `ZoneSyncEngine` need, protocol-injected so tests never touch a real
/// `CKContainer` (docs/11 §4).
public protocol CloudKitGateway: Sendable {
    func fetchOrCreateZone(_ zoneID: CKRecordZone.ID) async throws -> CKRecordZone
    func save(_ records: [CKRecord]) async throws -> [CKRecord]
    func delete(_ recordIDs: [CKRecord.ID]) async throws

    /// The incremental fetch loop's single page (docs/02 §6, NSP-036).
    /// `cursor: nil` fetches everything from the beginning of the zone.
    func fetchChanges(in zoneID: CKRecordZone.ID, since cursor: SyncCursor?) async throws -> ZoneChanges
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

    public func fetchChanges(in zoneID: CKRecordZone.ID, since cursor: SyncCursor?) async throws -> ZoneChanges {
        let changeToken = try cursor.map(Self.decodeChangeToken)
        let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: changeToken)
        let changedRecords = result.modificationResultsByID.values.compactMap { try? $0.get().record }
        let deletedRecordIDs = result.deletions.map(\.recordID)
        return ZoneChanges(
            changedRecords: changedRecords, deletedRecordIDs: deletedRecordIDs,
            cursor: try Self.encodeChangeToken(result.changeToken), moreComing: result.moreComing)
    }

    private static func encodeChangeToken(_ token: CKServerChangeToken) throws -> SyncCursor {
        SyncCursor(data: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
    }

    private static func decodeChangeToken(_ cursor: SyncCursor) throws -> CKServerChangeToken {
        guard
            let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self, from: cursor.data)
        else {
            throw SyncError.malformedField(record: "CKServerChangeToken", field: "cursor")
        }
        return token
    }
}
