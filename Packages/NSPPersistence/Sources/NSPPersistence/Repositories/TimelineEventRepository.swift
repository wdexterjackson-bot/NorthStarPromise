import Foundation
@preconcurrency import GRDB
import NSPCore

/// Append and query paths for `TimelineEvent` (NSP-012). No `update` — the
/// timeline is append-only, its entries never revised (docs/02 §2:
/// "makes the timeline explainable").
public protocol TimelineEventRepository: Sendable {
    func append(_ event: TimelineEvent, at date: Date) async throws
    func fetchAll(owner: ContentOwnerRef) async throws -> [TimelineEvent]
}

public struct GRDBTimelineEventRepository: TimelineEventRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func append(_ event: TimelineEvent, at date: Date) async throws {
        let row = try TimelineEventRow(event: event, createdAt: date, updatedAt: date, rowRevision: 1)
        try await dbWriter.write { db in
            try row.insert(db)
        }
    }

    /// Ordered by `sampleOffset` — the only ordering key that matters
    /// (docs/03 §4), never by `wallClock`.
    public func fetchAll(owner: ContentOwnerRef) async throws -> [TimelineEvent] {
        let encoded = ContentOwnerRefColumns.encode(owner)
        let rows = try await dbWriter.read { db in
            try TimelineEventRow
                .filter(Column("meeting_id") == encoded.id && Column("owner_kind") == encoded.kind)
                .order(Column("sample_offset"))
                .fetchAll(db)
        }
        return try rows.map { try $0.asDomain() }
    }
}
