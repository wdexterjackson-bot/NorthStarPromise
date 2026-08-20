import Foundation
import NSPCore
import NSPPersistence

/// In-memory `NoteBlockRepository` so tests never touch a real database
/// (docs/11 §4, NSP-047).
public actor FakeNoteBlockRepository: NoteBlockRepository {
    private var storage: [NoteBlockID: NoteBlock] = [:]

    public init() {}

    public func insert(_ block: NoteBlock, at date: Date) async throws {
        storage[block.blockID] = block
    }

    public func update(_ block: NoteBlock, at date: Date) async throws {
        guard storage[block.blockID] != nil else {
            throw PersistenceError.notFound(table: "note_block", key: block.blockID.description)
        }
        storage[block.blockID] = block
    }

    public func find(_ id: NoteBlockID) async throws -> NoteBlock? {
        storage[id]
    }

    public func fetchAll(meetingID: MeetingID) async throws -> [NoteBlock] {
        storage.values.filter { $0.meetingID == meetingID }
    }
}
