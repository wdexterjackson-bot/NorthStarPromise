import Foundation
import NSPCore

/// One row of the Watch's local meeting index (docs/09 NSP-027) — enough
/// for the Watch UI to list "My Recordings" and later reconcile with the
/// phone (Epic C), without pulling in the full GRDB stack `AppDatabase`
/// (NSP-011) was built for. Deliberately minimal: no transcript, no notes,
/// nothing that isn't already known the instant a meeting is armed or a
/// segment closes.
public struct WatchMeetingIndexEntry: Sendable, Hashable, Codable, Identifiable {
    public let meetingID: MeetingID
    public var id: MeetingID { meetingID }

    public let createdAt: Date
    public var state: MeetingState
    public var captureMode: CaptureMode
    public var segmentCount: Int
    public var updatedAt: Date

    public init(
        meetingID: MeetingID, createdAt: Date, state: MeetingState, captureMode: CaptureMode,
        segmentCount: Int = 0, updatedAt: Date
    ) {
        self.meetingID = meetingID
        self.createdAt = createdAt
        self.state = state
        self.captureMode = captureMode
        self.segmentCount = segmentCount
        self.updatedAt = updatedAt
    }
}

/// The Watch's own meeting index, independent of the phone (docs/09
/// NSP-027: "no dependency on the phone"). Protocol-fronted so Watch UI
/// code and tests never touch the real filesystem directly.
public protocol WatchLocalStore: Sendable {
    func upsert(_ entry: WatchMeetingIndexEntry) async throws
    func remove(_ meetingID: MeetingID) async throws
    func all() async throws -> [WatchMeetingIndexEntry]
    func find(_ meetingID: MeetingID) async throws -> WatchMeetingIndexEntry?
}

/// A single JSON-array file holding every entry, rewritten atomically on
/// every mutation (docs/09 NSP-027). An actor so concurrent upserts from
/// segment-close and timeline-event callers never interleave a read-modify-
/// write cycle.
public actor FileBackedWatchLocalStore: WatchLocalStore {
    private let indexURL: URL
    private let fileSystem: any WatchIndexFileSystem
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// `indexURL` is a single file — conventionally
    /// `<AppContainer>/watch-index.json` — not a per-meeting path, since
    /// this indexes every meeting the Watch knows about.
    public init(indexURL: URL, fileSystem: some WatchIndexFileSystem) {
        self.indexURL = indexURL
        self.fileSystem = fileSystem

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    public func upsert(_ entry: WatchMeetingIndexEntry) throws {
        var entries = try loadAll()
        if let index = entries.firstIndex(where: { $0.meetingID == entry.meetingID }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save(entries)
    }

    public func remove(_ meetingID: MeetingID) throws {
        var entries = try loadAll()
        entries.removeAll { $0.meetingID == meetingID }
        try save(entries)
    }

    public func all() throws -> [WatchMeetingIndexEntry] {
        try loadAll()
    }

    public func find(_ meetingID: MeetingID) throws -> WatchMeetingIndexEntry? {
        try loadAll().first { $0.meetingID == meetingID }
    }

    private func loadAll() throws -> [WatchMeetingIndexEntry] {
        guard fileSystem.fileExists(at: indexURL) else { return [] }
        let data = try fileSystem.readData(at: indexURL)
        guard !data.isEmpty else { return [] }
        return try jsonDecoder.decode([WatchMeetingIndexEntry].self, from: data)
    }

    private func save(_ entries: [WatchMeetingIndexEntry]) throws {
        let data = try jsonEncoder.encode(entries)
        try fileSystem.writeAndFsync(data, to: indexURL)
    }
}
