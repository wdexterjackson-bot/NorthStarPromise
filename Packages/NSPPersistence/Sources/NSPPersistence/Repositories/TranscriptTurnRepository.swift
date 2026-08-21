import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `TranscriptTurn` — the canonical batch pass's output (docs/04
/// §1's stage (c)). Protocol-fronted so tests use a fake instead of
/// touching a real database (docs/11 §4).
public protocol TranscriptTurnRepository: Sendable {
    func insert(_ turn: TranscriptTurn, at date: Date) async throws
    func update(_ turn: TranscriptTurn, at date: Date) async throws
    func find(_ id: TranscriptTurnID) async throws -> TranscriptTurn?
    /// Ordered by the first token's `startSample` — the canonical reading
    /// order for a transcript, never insertion order.
    func fetchAll(owner: ContentOwnerRef) async throws -> [TranscriptTurn]
    func delete(_ id: TranscriptTurnID) async throws
}

public struct GRDBTranscriptTurnRepository: TranscriptTurnRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ turn: TranscriptTurn, at date: Date) async throws {
        let row = TranscriptTurnRow(
            turn: turn, createdAt: date, updatedAt: date, rowRevision: 1, cloudRecordChangeTag: nil)
        try await dbWriter.write { db in
            try row.insert(db)
            try Self.syncChildren(db, turnID: row.turnID, turn: turn)
        }
    }

    public func update(_ turn: TranscriptTurn, at date: Date) async throws {
        let turnID = turn.turnID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try TranscriptTurnRow.fetchOne(db, key: turnID) else {
                throw PersistenceError.notFound(table: TranscriptTurnRow.databaseTableName, key: turnID)
            }
            let updated = TranscriptTurnRow(
                turn: turn, createdAt: existing.createdAt, updatedAt: date, rowRevision: existing.rowRevision + 1,
                cloudRecordChangeTag: existing.cloudRecordChangeTag)
            try updated.update(db)
            try Self.syncChildren(db, turnID: turnID, turn: turn)
        }
    }

    public func find(_ id: TranscriptTurnID) async throws -> TranscriptTurn? {
        try await dbWriter.read { db in
            guard let row = try TranscriptTurnRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try Self.assemble(row, in: db)
        }
    }

    public func fetchAll(owner: ContentOwnerRef) async throws -> [TranscriptTurn] {
        let encoded = ContentOwnerRefColumns.encode(owner)
        return try await dbWriter.read { db in
            let rows =
                try TranscriptTurnRow
                .filter(Column("meeting_id") == encoded.id && Column("owner_kind") == encoded.kind)
                .fetchAll(db)
            let turns = try rows.map { try Self.assemble($0, in: db) }
            return turns.sorted { ($0.tokens.first?.startSample ?? 0) < ($1.tokens.first?.startSample ?? 0) }
        }
    }

    public func delete(_ id: TranscriptTurnID) async throws {
        try await dbWriter.write { db in
            _ = try TranscriptTurnRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }

    // MARK: - Helpers

    private static func assemble(_ row: TranscriptTurnRow, in db: Database) throws -> TranscriptTurn {
        let tokens =
            try TranscriptTokenRow
            .filter(Column("turn_id") == row.turnID)
            .order(Column("position"))
            .fetchAll(db)
            .map { $0.asDomain() }
        let languageSpans =
            try TranscriptLanguageSpanRow
            .filter(Column("turn_id") == row.turnID)
            .order(Column("position"))
            .fetchAll(db)
            .map { $0.asDomain() }
        let segmentRefs =
            try TranscriptTurnSegmentRow
            .filter(Column("turn_id") == row.turnID)
            .order(Column("position"))
            .fetchAll(db)
            .map { try $0.asDomain() }
        return try row.asDomain(tokens: tokens, languageSpans: languageSpans, segmentRefs: segmentRefs)
    }

    /// Full replace of every child row, not a diff — same "accumulation is
    /// a bug" pattern as `GRDBNoteBlockRepository`'s opLog handling.
    private static func syncChildren(_ db: Database, turnID: String, turn: TranscriptTurn) throws {
        try db.execute(sql: "DELETE FROM transcript_token WHERE turn_id = ?", arguments: [turnID])
        for (position, token) in turn.tokens.enumerated() {
            try TranscriptTokenRow(turnID: turnID, position: position, token: token).insert(db)
        }
        try db.execute(sql: "DELETE FROM transcript_language_span WHERE turn_id = ?", arguments: [turnID])
        for (position, span) in turn.languageSpans.enumerated() {
            try TranscriptLanguageSpanRow(turnID: turnID, position: position, span: span).insert(db)
        }
        try db.execute(sql: "DELETE FROM transcript_turn_segment WHERE turn_id = ?", arguments: [turnID])
        for (position, segmentID) in turn.segmentRefs.enumerated() {
            try TranscriptTurnSegmentRow(turnID: turnID, segmentID: segmentID.rawValue.uuidString, position: position)
                .insert(db)
        }
    }
}
