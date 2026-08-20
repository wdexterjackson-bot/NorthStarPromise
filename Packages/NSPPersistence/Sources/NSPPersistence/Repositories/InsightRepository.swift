import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for `Insight` — generated summary/recap bullets (docs/02 §5).
/// Protocol-fronted so tests use a fake instead of touching a real database
/// (docs/11 §4).
public protocol InsightRepository: Sendable {
    func insert(_ insight: Insight, at date: Date) async throws
    func update(_ insight: Insight, at date: Date) async throws
    func find(_ id: InsightID) async throws -> Insight?
    func fetchAll(meetingID: MeetingID) async throws -> [Insight]
    func delete(_ id: InsightID) async throws
}

public struct GRDBInsightRepository: InsightRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ insight: Insight, at date: Date) async throws {
        let row = InsightRow(
            insight: insight, createdAt: date, updatedAt: date, rowRevision: 1, cloudRecordChangeTag: nil)
        try await dbWriter.write { db in
            try row.insert(db)
            try EvidenceSpanPersistence.sync(
                db, owner: .insight(row.insightID), meetingID: row.meetingID, spans: insight.evidence)
        }
    }

    public func update(_ insight: Insight, at date: Date) async throws {
        let insightID = insight.insightID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try InsightRow.fetchOne(db, key: insightID) else {
                throw PersistenceError.notFound(table: InsightRow.databaseTableName, key: insightID)
            }
            let updated = InsightRow(
                insight: insight, createdAt: existing.createdAt, updatedAt: date,
                rowRevision: existing.rowRevision + 1, cloudRecordChangeTag: existing.cloudRecordChangeTag)
            try updated.update(db)
            try EvidenceSpanPersistence.sync(
                db, owner: .insight(insightID), meetingID: updated.meetingID, spans: insight.evidence)
        }
    }

    public func find(_ id: InsightID) async throws -> Insight? {
        try await dbWriter.read { db in
            guard let row = try InsightRow.fetchOne(db, key: id.rawValue.uuidString) else { return nil }
            return try row.asDomain(evidence: try EvidenceSpanPersistence.fetch(db, owner: .insight(row.insightID)))
        }
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Insight] {
        try await dbWriter.read { db in
            let rows =
                try InsightRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .order(Column("created_at"))
                .fetchAll(db)
            return try rows.map { row in
                try row.asDomain(evidence: try EvidenceSpanPersistence.fetch(db, owner: .insight(row.insightID)))
            }
        }
    }

    public func delete(_ id: InsightID) async throws {
        try await dbWriter.write { db in
            _ = try InsightRow.deleteOne(db, key: id.rawValue.uuidString)
        }
    }
}
