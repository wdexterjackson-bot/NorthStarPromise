import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Note` — standalone, never a disguised `Meeting`, even once it
/// carries an attached recording. Same shape as `BrainDumpRepository`.
public protocol NoteRepository: Sendable {
    func insert(_ note: Note, at date: Date) async throws
    func update(_ note: Note, at date: Date) async throws
    func find(_ id: NoteID) async throws -> Note?
    func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Note]
    /// See `MeetingRepository.delete`'s doc comment — explicit
    /// `OwnedContentCleanup`, not a SQL cascade.
    func delete(_ id: NoteID) async throws
}

public struct GRDBNoteRepository: NoteRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ note: Note, at date: Date) async throws {
        let row = NoteRow(note: note, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in try row.insert(db) }
    }

    public func update(_ note: Note, at date: Date) async throws {
        let noteID = note.noteID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try NoteRow.fetchOne(db, key: noteID) else {
                throw PersistenceError.notFound(table: NoteRow.databaseTableName, key: noteID)
            }
            let updated = NoteRow(
                note: note, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: NoteID) async throws -> Note? {
        let row = try await dbWriter.read { db in
            try NoteRow.fetchOne(db, key: id.rawValue.uuidString)
        }
        return try row.map { try $0.asDomain() }
    }

    public func fetchAll(workspaceID: WorkspaceID, includeDeleted: Bool) async throws -> [Note] {
        try await dbWriter.read { db in
            var request = NoteRow.filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
            if !includeDeleted {
                request = request.filter(Column("deleted_at") == nil)
            }
            let rows = try request.order(Column("started_at").desc).fetchAll(db)
            return try rows.map { try $0.asDomain() }
        }
    }

    public func delete(_ id: NoteID) async throws {
        try await dbWriter.write { db in
            try OwnedContentCleanup.deleteAll(for: .note(id), in: db)
            _ = try NoteRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }
}
