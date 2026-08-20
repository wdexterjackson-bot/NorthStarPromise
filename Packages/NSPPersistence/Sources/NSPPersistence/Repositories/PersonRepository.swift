import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Person`. Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol PersonRepository: Sendable {
    func insert(_ person: Person, at date: Date) async throws
    func find(_ id: PersonID) async throws -> Person?
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

    public func find(_ id: PersonID) async throws -> Person? {
        try await dbWriter.read { db in
            guard let row = try PersonRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try row.asDomain(aliases: try Self.fetchAliases(personID: row.personID, in: db))
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
