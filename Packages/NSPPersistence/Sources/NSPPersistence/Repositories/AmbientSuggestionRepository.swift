import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD + the Ambient Suggestions inbox query for `AmbientSuggestion`
/// (NSP-161/164, "Overheard"). Protocol-fronted so tests use a fake instead
/// of touching a real database (docs/11 §4).
public protocol AmbientSuggestionRepository: Sendable {
    func insert(_ suggestion: AmbientSuggestion, at date: Date) async throws
    func update(_ suggestion: AmbientSuggestion, at date: Date) async throws
    func delete(_ id: AmbientSuggestionID) async throws
    /// The inbox — every suggestion still awaiting a human decision,
    /// newest first (matches the order they'd have arrived while listening).
    func fetchPending(workspaceID: WorkspaceID) async throws -> [AmbientSuggestion]
}

public struct GRDBAmbientSuggestionRepository: AmbientSuggestionRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ suggestion: AmbientSuggestion, at date: Date) async throws {
        let row = AmbientSuggestionRow(suggestion: suggestion, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ suggestion: AmbientSuggestion, at date: Date) async throws {
        let id = suggestion.ambientSuggestionID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try AmbientSuggestionRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: AmbientSuggestionRow.databaseTableName, key: id)
            }
            let updated = AmbientSuggestionRow(
                suggestion: suggestion, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func delete(_ id: AmbientSuggestionID) async throws {
        try await dbWriter.write { db in
            _ = try AmbientSuggestionRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    public func fetchPending(workspaceID: WorkspaceID) async throws -> [AmbientSuggestion] {
        try await dbWriter.read { db in
            try AmbientSuggestionRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .filter(Column("status") == AmbientSuggestionStatus.pending.rawValue)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }
}
