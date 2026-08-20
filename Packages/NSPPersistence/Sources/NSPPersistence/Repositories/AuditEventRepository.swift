import Foundation
@preconcurrency import GRDB
import NSPCore

/// Append-only CRUD for `AuditEvent` — `insert` only, no `update`, matching
/// the table's own append-only design (docs/06 §11).
public protocol AuditEventRepository: Sendable {
    func insert(_ event: AuditEvent, at date: Date) async throws
    func find(_ id: AuditEventID) async throws -> AuditEvent?
}

public struct GRDBAuditEventRepository: AuditEventRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    /// `date` is accepted for signature symmetry with every other
    /// repository in this package, but the row's own `timestamp` (already
    /// on `AuditEvent`) is what's persisted — there's no separate
    /// `created_at` column to stamp here.
    public func insert(_ event: AuditEvent, at date: Date) async throws {
        let row = AuditEventRow(event: event)
        try await dbWriter.write { db in try row.insert(db) }
    }

    public func find(_ id: AuditEventID) async throws -> AuditEvent? {
        try await dbWriter.read { db in
            try AuditEventRow.fetchOne(db, key: id.rawValue.uuidString)?.asDomain()
        }
    }
}
