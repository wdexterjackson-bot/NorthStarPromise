import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD and query paths for `Action` (NSP-048/NSP-049's persistence half).
/// Protocol-fronted so tests use a fake instead of touching a real database
/// (docs/11 §4).
public protocol ActionRepository: Sendable {
    func insert(_ action: Action, at date: Date) async throws
    func update(_ action: Action, at date: Date) async throws
    func find(_ id: ActionID) async throws -> Action?
    func fetchAll(meetingID: MeetingID) async throws -> [Action]
    /// Every action in the workspace, meeting-tied or freestanding — what
    /// the global Actions dashboard (docs/07 §4) groups by status.
    /// `action_item.workspace_id` is its own real column (not derived via
    /// a `meeting` join) precisely so a freestanding action still surfaces
    /// here.
    func fetchAll(workspaceID: WorkspaceID) async throws -> [Action]
    func delete(_ id: ActionID) async throws
}

public struct GRDBActionRepository: ActionRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ action: Action, at date: Date) async throws {
        let row = ActionRow(action: action, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.replaceAuditTrail(action.auditTrail, actionID: row.actionID, in: db)
            try Self.syncEvidence(db, actionID: row.actionID, meetingID: row.meetingID, spans: action.evidence)
        }
    }

    public func update(_ action: Action, at date: Date) async throws {
        let actionID = action.actionID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try ActionRow.fetchOne(db, key: actionID) else {
                throw PersistenceError.notFound(table: ActionRow.databaseTableName, key: actionID)
            }
            let updated = ActionRow(
                action: action, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
            try Self.replaceAuditTrail(action.auditTrail, actionID: actionID, in: db)
            try Self.syncEvidence(db, actionID: actionID, meetingID: updated.meetingID, spans: action.evidence)
        }
    }

    /// A span always needs a real meeting's transcript to quote from
    /// (Invariant I4), so a freestanding action (`meetingID == nil`) can
    /// only ever clear its evidence, never insert any — `evidence` should
    /// already be empty for one, but this makes that the enforced outcome
    /// rather than an assumption.
    private static func syncEvidence(
        _ db: Database, actionID: String, meetingID: String?, spans: [EvidenceSpan]
    ) throws {
        if let meetingID {
            try EvidenceSpanPersistence.sync(db, owner: .action(actionID), meetingID: meetingID, spans: spans)
        } else {
            try EvidenceSpanPersistence.clear(db, owner: .action(actionID))
        }
    }

    public func find(_ id: ActionID) async throws -> Action? {
        try await dbWriter.read { db in
            guard let row = try ActionRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try row.asDomain(
                evidence: try EvidenceSpanPersistence.fetch(db, owner: .action(row.actionID)),
                auditTrail: try Self.fetchAuditTrail(actionID: row.actionID, in: db))
        }
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Action] {
        try await dbWriter.read { db in
            let rows =
                try ActionRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .order(Column("created_at"))
                .fetchAll(db)
            return try rows.map { row in
                try row.asDomain(
                    evidence: try EvidenceSpanPersistence.fetch(db, owner: .action(row.actionID)),
                    auditTrail: try Self.fetchAuditTrail(actionID: row.actionID, in: db))
            }
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [Action] {
        try await dbWriter.read { db in
            let rows =
                try ActionRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .order(Column("created_at"))
                .fetchAll(db)
            return try rows.map { row in
                try row.asDomain(
                    evidence: try EvidenceSpanPersistence.fetch(db, owner: .action(row.actionID)),
                    auditTrail: try Self.fetchAuditTrail(actionID: row.actionID, in: db))
            }
        }
    }

    public func delete(_ id: ActionID) async throws {
        try await dbWriter.write { db in
            _ = try ActionRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    private static func fetchAuditTrail(actionID: String, in db: Database) throws -> [AuditEntry] {
        try ActionAuditEntryRow
            .filter(Column("action_id") == actionID)
            .order(Column("position"))
            .fetchAll(db)
            .map { try $0.asDomain() }
    }

    /// Full replace, not a diff — same "accumulation is a bug" pattern as
    /// `GRDBNoteBlockRepository`'s opLog handling.
    private static func replaceAuditTrail(_ auditTrail: [AuditEntry], actionID: String, in db: Database) throws {
        try ActionAuditEntryRow.filter(Column("action_id") == actionID).deleteAll(db)
        for (index, entry) in auditTrail.enumerated() {
            try ActionAuditEntryRow(actionID: actionID, position: index, entry: entry).insert(db)
        }
    }
}
