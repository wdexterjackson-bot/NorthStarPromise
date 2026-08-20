import Foundation
import NSPCore
import NSPPersistence

/// In-memory `SegmentRepository` so tests never touch a real database
/// (docs/11 §4, NSP-012).
public actor FakeSegmentRepository: SegmentRepository {
    private var storage: [SegmentID: Segment] = [:]

    public init() {}

    public func insert(_ segment: Segment, at date: Date) async throws {
        storage[segment.segmentID] = segment
    }

    public func update(_ segment: Segment, at date: Date) async throws {
        guard storage[segment.segmentID] != nil else {
            throw PersistenceError.notFound(table: "segment", key: segment.segmentID.description)
        }
        storage[segment.segmentID] = segment
    }

    public func find(_ id: SegmentID) async throws -> Segment? {
        storage[id]
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [Segment] {
        storage.values
            .filter { $0.meetingID == meetingID }
            .sorted { $0.sequence < $1.sequence }
    }

    public func findUploaded(sha256: Data) async throws -> Segment? {
        storage.values.first { $0.sha256 == sha256 && $0.cloudAssetRef != nil }
    }
}
