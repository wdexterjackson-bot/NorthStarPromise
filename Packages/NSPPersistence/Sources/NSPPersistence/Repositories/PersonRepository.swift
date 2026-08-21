import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Person`. Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol PersonRepository: Sendable {
    func insert(_ person: Person, at date: Date) async throws
    func update(_ person: Person, at date: Date) async throws
    func find(_ id: PersonID) async throws -> Person?
    /// Every person in the workspace — "the list of active people you're
    /// meeting with" (People feature) — `self` (`AppEnvironment
    /// .selfPersonID`) included.
    func fetchAll(workspaceID: WorkspaceID) async throws -> [Person]
    func delete(_ id: PersonID) async throws
}

public struct GRDBPersonRepository: PersonRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ person: Person, at date: Date) async throws {
        let row = PersonRow(person: person, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.replaceAliases(person.aliases, personID: row.personID, in: db)
        }
    }

    public func update(_ person: Person, at date: Date) async throws {
        let id = person.personID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try PersonRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: PersonRow.databaseTableName, key: id)
            }
            let updated = PersonRow(
                person: person, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
            try Self.replaceAliases(person.aliases, personID: id, in: db)
        }
    }

    public func find(_ id: PersonID) async throws -> Person? {
        try await dbWriter.read { db in
            guard let row = try PersonRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try row.asDomain(aliases: try Self.fetchAliases(personID: row.personID, in: db))
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [Person] {
        try await dbWriter.read { db in
            try PersonRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .order(Column("name"))
                .fetchAll(db)
                .map { row in try row.asDomain(aliases: try Self.fetchAliases(personID: row.personID, in: db)) }
        }
    }

    public func delete(_ id: PersonID) async throws {
        try await dbWriter.write { db in
            _ = try PersonRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    private static func fetchAliases(personID: String, in db: Database) throws -> [String] {
        try PersonAliasRow
            .filter(Column("person_id") == personID)
            .order(Column("position"))
            .fetchAll(db)
            .map(\.alias)
    }

    /// Full replace, not a diff — same "accumulation is a bug" pattern as
    /// `GRDBNoteBlockRepository`'s opLog handling.
    private static func replaceAliases(_ aliases: [String], personID: String, in db: Database) throws {
        try PersonAliasRow.filter(Column("person_id") == personID).deleteAll(db)
        for (index, alias) in aliases.enumerated() {
            try PersonAliasRow(personID: personID, position: index, alias: alias).insert(db)
        }
    }
}
