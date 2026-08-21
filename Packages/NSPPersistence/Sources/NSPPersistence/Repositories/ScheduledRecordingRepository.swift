import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD and query paths for `ScheduledRecording` (docs/07 §2.1's
/// persistence half). Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol ScheduledRecordingRepository: Sendable {
    func insert(_ item: ScheduledRecording, at date: Date) async throws
    func update(_ item: ScheduledRecording, at date: Date) async throws
    func find(_ id: ScheduledRecordingID) async throws -> ScheduledRecording?
    /// Everything not yet resolved (`.pending`/`.notified`) — the source
    /// list for both the Today "Upcoming" section and the app-launch
    /// reconciliation pass.
    func fetchPending(workspaceID: WorkspaceID) async throws -> [ScheduledRecording]
    func fetchAll(workspaceID: WorkspaceID) async throws -> [ScheduledRecording]
    func delete(_ id: ScheduledRecordingID) async throws
}

public struct GRDBScheduledRecordingRepository: ScheduledRecordingRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ item: ScheduledRecording, at date: Date) async throws {
        let row = ScheduledRecordingRow(item: item, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ item: ScheduledRecording, at date: Date) async throws {
        let id = item.scheduledRecordingID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try ScheduledRecordingRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: ScheduledRecordingRow.databaseTableName, key: id)
            }
            let updated = ScheduledRecordingRow(
                item: item, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: ScheduledRecordingID) async throws -> ScheduledRecording? {
        try await dbWriter.read { db in
            try ScheduledRecordingRow.fetchOne(db, key: id.rawValue.uuidString)?.asDomain()
        }
    }

    public func fetchPending(workspaceID: WorkspaceID) async throws -> [ScheduledRecording] {
        try await dbWriter.read { db in
            try ScheduledRecordingRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .filter(["pending", "notified"].contains(Column("status")))
                .order(Column("scheduled_start"))
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [ScheduledRecording] {
        try await dbWriter.read { db in
            try ScheduledRecordingRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .order(Column("scheduled_start"))
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }

    public func delete(_ id: ScheduledRecordingID) async throws {
        try await dbWriter.write { db in
            _ = try ScheduledRecordingRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }
}
