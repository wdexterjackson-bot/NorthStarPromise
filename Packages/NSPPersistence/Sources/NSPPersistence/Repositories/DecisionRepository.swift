import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Decision` — same shape as `ActionRepository`. Protocol-fronted
/// so tests use a fake instead of touching a real database (docs/11 §4).
public protocol DecisionRepository: Sendable {
    func insert(_ decision: Decision, at date: Date) async throws
    func update(_ decision: Decision, at date: Date) async throws
    func find(_ id: DecisionID) async throws -> Decision?
    func fetchAll(meetingID: MeetingID) async throws -> [Decision]
    /// Every decision across every meeting in the workspace — the source
    /// list for cross-meeting views (a person's "recent decisions," a
    /// thread's aggregated decisions).
    func fetchAll(workspaceID: WorkspaceID) async throws -> [Decision]
    func delete(_ id: DecisionID) async throws
}

public struct GRDBDecisionRepository: DecisionRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ decision: Decision, at date: Date) async throws {
        let row = DecisionRow(decision: decision, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.replaceAlternatives(decision.alternativesConsidered, decisionID: row.decisionID, in: db)
            try Self.replaceAuditTrail(decision.auditTrail, decisionID: row.decisionID, in: db)
            try EvidenceSpanPersistence.sync(
                db, owner: .decision(row.decisionID), meetingID: row.meetingID, spans: decision.evidence)
        }
    }

    public func update(_ decision: Decision, at date: Date) async throws {
        let id = decision.decisionID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try DecisionRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: DecisionRow.databaseTableName, key: id)
            }
            let updated = DecisionRow(
                decision: decision, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1)
            try updated.update(db)
            try Self.replaceAlternatives(decision.alternativesConsidered, decisionID: id, in: db)
            try Self.replaceAuditTrail(decision.auditTrail, decisionID: id, in: db)
            try EvidenceSpanPersistence.sync(
                db, owner: .decision(id), meetingID: updated.meetingID, spans: decision.evidence)
        }
    }

    public func find(_ id: DecisionID) async throws -> Decision? {
        try await dbWriter.read { db in
            try Self.load(db, decisionID: id.rawValue.uuidString)
        }
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Decision] {
        try await dbWriter.read { db in
            try DecisionRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .fetchAll(db)
                .map { try Self.load(db, row: $0) }
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [Decision] {
        try await dbWriter.read { db in
            try DecisionRow
                .filter(
                    sql: "meeting_id IN (SELECT meeting_id FROM meeting WHERE workspace_id = ?)",
                    arguments: [workspaceID.rawValue.uuidString]
                )
                .fetchAll(db)
                .map { try Self.load(db, row: $0) }
        }
    }

    public func delete(_ id: DecisionID) async throws {
        try await dbWriter.write { db in
            _ = try DecisionRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    private static func load(_ db: Database, decisionID: String) throws -> Decision? {
        guard let row = try DecisionRow.fetchOne(db, key: decisionID) else { return nil }
        return try Self.load(db, row: row)
    }

    private static func load(_ db: Database, row: DecisionRow) throws -> Decision {
        let alternatives =
            try DecisionAlternativeRow
            .filter(Column("decision_id") == row.decisionID)
            .order(Column("position"))
            .fetchAll(db)
            .map(\.text)
        let auditTrail =
            try DecisionAuditEntryRow
            .filter(Column("decision_id") == row.decisionID)
            .order(Column("position"))
            .fetchAll(db)
            .map { try $0.asDomain() }
        let evidence = try EvidenceSpanPersistence.fetch(db, owner: .decision(row.decisionID))
        return try row.asDomain(evidence: evidence, alternativesConsidered: alternatives, auditTrail: auditTrail)
    }

    private static func replaceAlternatives(_ alternatives: [String], decisionID: String, in db: Database) throws {
        try DecisionAlternativeRow.filter(Column("decision_id") == decisionID).deleteAll(db)
        for (position, text) in alternatives.enumerated() {
            try DecisionAlternativeRow(decisionID: decisionID, position: position, text: text).insert(db)
        }
    }

    private static func replaceAuditTrail(_ auditTrail: [AuditEntry], decisionID: String, in db: Database) throws {
        try DecisionAuditEntryRow.filter(Column("decision_id") == decisionID).deleteAll(db)
        for (position, entry) in auditTrail.enumerated() {
            try DecisionAuditEntryRow(decisionID: decisionID, position: position, entry: entry).insert(db)
        }
    }
}
