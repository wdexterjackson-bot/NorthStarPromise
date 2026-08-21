import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `BrainDump` — a real recording that isn't a meeting. Same
/// shape as `MeetingRepository`, minus the availability/missing-segment
/// machinery a Brain Dump has no use for.
public protocol BrainDumpRepository: Sendable {
    func insert(_ brainDump: BrainDump, at date: Date) async throws
    func update(_ brainDump: BrainDump, at date: Date) async throws
    func find(_ id: BrainDumpID) async throws -> BrainDump?
    func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [BrainDump]
    /// Deletes the row and explicitly cleans up its segments/transcript
    /// turns/note blocks via `OwnedContentCleanup` — see
    /// `MeetingRepository.delete`'s doc comment for why that's explicit
    /// now rather than a SQL cascade.
    func delete(_ id: BrainDumpID) async throws
}

public struct GRDBBrainDumpRepository: BrainDumpRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ brainDump: BrainDump, at date: Date) async throws {
        let row = BrainDumpRow(brainDump: brainDump, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in try row.insert(db) }
    }

    public func update(_ brainDump: BrainDump, at date: Date) async throws {
        let brainDumpID = brainDump.brainDumpID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try BrainDumpRow.fetchOne(db, key: brainDumpID) else {
                throw PersistenceError.notFound(table: BrainDumpRow.databaseTableName, key: brainDumpID)
            }
            let updated = BrainDumpRow(
                brainDump: brainDump, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: BrainDumpID) async throws -> BrainDump? {
        let row = try await dbWriter.read { db in
            try BrainDumpRow.fetchOne(db, key: id.rawValue.uuidString)
        }
        return try row.map { try $0.asDomain() }
    }

    public func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [BrainDump] {
        try await dbWriter.read { db in
            var request = BrainDumpRow.filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
            if !includeDeleted {
                request = request.filter(Column("deleted_at") == nil)
            }
            let rows = try request.order(Column("started_at").desc).fetchAll(db)
            return try rows.map { try $0.asDomain() }
        }
    }

    public func delete(_ id: BrainDumpID) async throws {
        try await dbWriter.write { db in
            try OwnedContentCleanup.deleteAll(for: .brainDump(id), in: db)
            _ = try BrainDumpRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }
}
