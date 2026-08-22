import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `RecurrenceRule` (NSP-157). Protocol-fronted so tests use a
/// fake instead of touching a real database (docs/11 §4).
public protocol RecurrenceRuleRepository: Sendable {
    func insert(_ rule: RecurrenceRule, at date: Date) async throws
    func update(_ rule: RecurrenceRule, at date: Date) async throws
    func find(_ id: RecurrenceRuleID) async throws -> RecurrenceRule?
    func fetchAll(workspaceID: WorkspaceID) async throws -> [RecurrenceRule]
    func delete(_ id: RecurrenceRuleID) async throws
}

public struct GRDBRecurrenceRuleRepository: RecurrenceRuleRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ rule: RecurrenceRule, at date: Date) async throws {
        let row = RecurrenceRuleRow(rule: rule, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ rule: RecurrenceRule, at date: Date) async throws {
        let id = rule.recurrenceRuleID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try RecurrenceRuleRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: RecurrenceRuleRow.databaseTableName, key: id)
            }
            let updated = RecurrenceRuleRow(
                rule: rule, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func find(_ id: RecurrenceRuleID) async throws -> RecurrenceRule? {
        try await dbWriter.read { db in
            try RecurrenceRuleRow.fetchOne(db, key: id.rawValue.uuidString)?.asDomain()
        }
    }

    public func fetchAll(workspaceID: WorkspaceID) async throws -> [RecurrenceRule] {
        try await dbWriter.read { db in
            try RecurrenceRuleRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }

    public func delete(_ id: RecurrenceRuleID) async throws {
        try await dbWriter.write { db in
            _ = try RecurrenceRuleRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }
}

/// CRUD for `RecurrenceException` (NSP-157/159).
public protocol RecurrenceExceptionRepository: Sendable {
    func insert(_ exception: RecurrenceException, at date: Date) async throws
    func update(_ exception: RecurrenceException, at date: Date) async throws
    func delete(_ id: RecurrenceExceptionID) async throws
    /// Every exception for one series — `RecurrenceExpander`'s caller
    /// applies these against the raw occurrence list (NSP-160).
    func fetchAll(recurrenceRuleID: RecurrenceRuleID) async throws -> [RecurrenceException]
}

public struct GRDBRecurrenceExceptionRepository: RecurrenceExceptionRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ exception: RecurrenceException, at date: Date) async throws {
        let row = RecurrenceExceptionRow(exception: exception, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ exception: RecurrenceException, at date: Date) async throws {
        let id = exception.recurrenceExceptionID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try RecurrenceExceptionRow.fetchOne(db, key: id) else {
                throw PersistenceError.notFound(table: RecurrenceExceptionRow.databaseTableName, key: id)
            }
            let updated = RecurrenceExceptionRow(
                exception: exception, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1)
            try updated.update(db)
        }
    }

    public func delete(_ id: RecurrenceExceptionID) async throws {
        try await dbWriter.write { db in
            _ = try RecurrenceExceptionRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    public func fetchAll(recurrenceRuleID: RecurrenceRuleID) async throws -> [RecurrenceException] {
        try await dbWriter.read { db in
            try RecurrenceExceptionRow
                .filter(Column("recurrence_rule_id") == recurrenceRuleID.rawValue.uuidString)
                .order(Column("original_occurrence_date"))
                .fetchAll(db)
                .map { try $0.asDomain() }
        }
    }
}
