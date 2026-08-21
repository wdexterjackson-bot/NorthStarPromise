import Foundation
import NSPCore
import NSPPersistence

/// In-memory `TimelineEventRepository` so tests never touch a real database
/// (docs/11 §4, NSP-012).
public actor FakeTimelineEventRepository: TimelineEventRepository {
    private var storage: [TimelineEvent] = []

    public init() {}

    public func append(_ event: TimelineEvent, at date: Date) async throws {
        storage.append(event)
    }

    public func fetchAll(owner: ContentOwnerRef) async throws -> [TimelineEvent] {
        storage
            .filter { $0.owner == owner }
            .sorted { $0.sampleOffset < $1.sampleOffset }
    }
}
