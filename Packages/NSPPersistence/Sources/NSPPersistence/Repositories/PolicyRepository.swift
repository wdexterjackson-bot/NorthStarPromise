import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Policy` (NSP-015). Every armed meeting freezes its own row —
/// see `PolicyRow`'s header comment — so `insert` is the common path;
/// `update` exists for the workspace's own live default policy, not for
/// already-frozen per-meeting snapshots (that rule is enforced by
/// `NSPPolicy`, not this module, which only stores what it's given).
public protocol PolicyRepository: Sendable {
    func insert(_ policy: Policy, at date: Date) async throws
    func update(_ policy: Policy, at date: Date) async throws
    func find(_ id: PolicyID) async throws -> Policy?
}

public struct GRDBPolicyRepository: PolicyRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ policy: Policy, at date: Date) async throws {
        let row = PolicyRow(policy: policy, createdAt: date, updatedAt: date, rowRevision: 1, cloudRecordChangeTag: nil)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.syncLists(db, policyID: row.policyID, policy: policy)
        }
    }

    public func update(_ policy: Policy, at date: Date) async throws {
        let policyID = policy.policyID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try PolicyRow.fetchOne(db, key: policyID) else {
                throw PersistenceError.notFound(table: PolicyRow.databaseTableName, key: policyID)
            }
            let updated = PolicyRow(
                policy: policy,
                createdAt: existing.createdAt,
                updatedAt: date,
                rowRevision: existing.rowRevision + 1,
                cloudRecordChangeTag: existing.cloudRecordChangeTag
            )
            try updated.update(db)
            try Self.syncLists(db, policyID: policyID, policy: policy)
        }
    }

    public func find(_ id: PolicyID) async throws -> Policy? {
        try await dbWriter.read { db in
            try Self.fetchPolicy(db, policyID: id.rawValue.uuidString)
        }
    }

    // MARK: - Helpers

    private static func fetchPolicy(_ db: Database, policyID: String) throws -> Policy? {
        guard let row = try PolicyRow.fetchOne(db, key: policyID) else { return nil }
        let domains =
            try PolicyBlockedDomainRow
            .filter(Column("policy_id") == policyID)
            .order(Column("position"))
            .fetchAll(db)
            .map(\.domain)
        let locations =
            try PolicyBlockedLocationRow
            .filter(Column("policy_id") == policyID)
            .order(Column("position"))
            .fetchAll(db)
            .map(\.location)
        return try row.asDomain(blockedDomains: domains, blockedLocations: locations)
    }

    /// Replaces every child row for this policy — same delete-then-reinsert
    /// approach `GRDBMeetingRepository` uses for its own small array field.
    private static func syncLists(_ db: Database, policyID: String, policy: Policy) throws {
        try db.execute(sql: "DELETE FROM policy_blocked_domain WHERE policy_id = ?", arguments: [policyID])
        for (position, domain) in policy.blockedDomains.enumerated() {
            try PolicyBlockedDomainRow(policyID: policyID, position: position, domain: domain).insert(db)
        }
        try db.execute(sql: "DELETE FROM policy_blocked_location WHERE policy_id = ?", arguments: [policyID])
        for (position, location) in policy.blockedLocations.enumerated() {
            try PolicyBlockedLocationRow(policyID: policyID, position: position, location: location).insert(db)
        }
    }
}
