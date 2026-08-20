import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD and query paths for `Segment` (NSP-012). Protocol-fronted so tests
/// use a fake instead of touching a real database (docs/11 §4).
public protocol SegmentRepository: Sendable {
    func insert(_ segment: Segment, at date: Date) async throws
    func update(_ segment: Segment, at date: Date) async throws
    func find(_ id: SegmentID) async throws -> Segment?
    func fetchAll(meetingID: MeetingID) async throws -> [Segment]

    /// The dedupe lookup behind "a duplicate upload collapses to the
    /// existing asset" (docs/02 §6, NSP-035): a previously uploaded segment
    /// sharing this content hash, if one exists. Only segments that already
    /// carry a `cloudAssetRef` are candidates — a hash match against a
    /// not-yet-uploaded segment isn't something to dedupe against.
    func findUploaded(sha256: Data) async throws -> Segment?
}

public struct GRDBSegmentRepository: SegmentRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func insert(_ segment: Segment, at date: Date) async throws {
        let row = SegmentRow(
            segment: segment, createdAt: date, updatedAt: date, rowRevision: 1, cloudRecordChangeTag: nil)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    public func update(_ segment: Segment, at date: Date) async throws {
        let segmentID = segment.segmentID.rawValue.uuidString
        try await dbWriter.write { db in
            guard let existing = try SegmentRow.fetchOne(db, key: segmentID) else {
                throw PersistenceError.notFound(table: SegmentRow.databaseTableName, key: segmentID)
            }
            let updated = SegmentRow(
                segment: segment,
                createdAt: existing.createdAt,
                updatedAt: date,
                rowRevision: existing.rowRevision + 1,
                cloudRecordChangeTag: existing.cloudRecordChangeTag
            )
            try updated.update(db)
        }
    }

    public func find(_ id: SegmentID) async throws -> Segment? {
        let row = try await dbWriter.read { db in
            try SegmentRow.fetchOne(db, key: id.rawValue.uuidString)
        }
        return try row.map { try $0.asDomain() }
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Segment] {
        let rows = try await dbWriter.read { db in
            try SegmentRow
                .filter(Column("meeting_id") == meetingID.rawValue.uuidString)
                .order(Column("sequence"))
                .fetchAll(db)
        }
        return try rows.map { try $0.asDomain() }
    }

    public func findUploaded(sha256: Data) async throws -> Segment? {
        let hex = sha256.map { String(format: "%02x", $0) }.joined()
        let row = try await dbWriter.read { db in
            try SegmentRow
                .filter(Column("sha256") == hex)
                .filter(Column("cloud_asset_ref") != nil)
                .fetchOne(db)
        }
        return try row.map { try $0.asDomain() }
    }
}
