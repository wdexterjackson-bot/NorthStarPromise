import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD and query paths for `NoteBlock` (NSP-047). Protocol-fronted so
/// tests use a fake instead of touching a real database (docs/11 §4).
public protocol NoteBlockRepository: Sendable {
    func insert(_ block: NoteBlock, at date: Date) async throws
    func update(_ block: NoteBlock, at date: Date) async throws
    func find(_ id: NoteBlockID) async throws -> NoteBlock?
    func fetchAll(meetingID: MeetingID) async throws -> [NoteBlock]
    func delete(_ id: NoteBlockID) async throws
}

public struct GRDBNoteBlockRepository: NoteBlockRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ block: NoteBlock, at date: Date) async throws {
        let row = NoteBlockRow(block: block, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.replaceOpLog(block.opLog, blockID: row.blockID, in: db)
        }
    }

    public func update(_ block: NoteBlock, at date: Date) async throws {
        let blockID = block.blockID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try NoteBlockRow.fetchOne(db, key: blockID) else {
                throw PersistenceError.notFound(table: NoteBlockRow.databaseTableName, key: blockID)
            }
            let updated = NoteBlockRow(
                block: block, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
            try Self.replaceOpLog(block.opLog, blockID: blockID, in: db)
        }
    }

    public func find(_ id: NoteBlockID) async throws -> NoteBlock? {
        try await dbWriter.read { db in
            guard let row = try NoteBlockRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try row.asDomain(opLog: try Self.fetchOpLog(blockID: row.blockID, in: db))
        }
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [NoteBlock] {
        try await dbWriter.read { db in
            let rows =
                try NoteBlockRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .fetchAll(db)
            return try rows.map { row in try row.asDomain(opLog: try Self.fetchOpLog(blockID: row.blockID, in: db)) }
        }
    }

    /// `note_operation` rows cascade on delete (the migration's
    /// `references("note_block", onDelete: .cascade)`), so no separate
    /// opLog cleanup is needed here.
    public func delete(_ id: NoteBlockID) async throws {
        try await dbWriter.write { db in
            _ = try NoteBlockRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    private static func fetchOpLog(blockID: String, in db: Database) throws -> [NSPCore.Operation] {
        try NoteOperationRow
            .filter(Column("block_id") == blockID)
            .order(Column("position"))
            .fetchAll(db)
            .map { try $0.asDomain() }
    }

    /// Full replace, not a diff — the same "accumulation is a bug" pattern
    /// as `GRDBMeetingRepository`'s blocked-list handling: `NoteBlock.opLog`
    /// is a value the caller hands over whole, so every write makes storage
    /// match it exactly.
    private static func replaceOpLog(_ opLog: [NSPCore.Operation], blockID: String, in db: Database) throws {
        try NoteOperationRow.filter(Column("block_id") == blockID).deleteAll(db)
        for (index, operation) in opLog.enumerated() {
            let row = NoteOperationRow(blockID: blockID, position: index, operation: operation)
            try row.insert(db)
        }
    }
}
