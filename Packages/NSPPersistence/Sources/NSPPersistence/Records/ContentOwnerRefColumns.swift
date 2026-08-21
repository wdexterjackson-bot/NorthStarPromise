import Foundation
import NSPCore

/// Shared encode/decode between `ContentOwnerRef` and the `(owner id,
/// owner kind)` column pair every polymorphic-owner table (`segment`,
/// `transcript_turn`, `note_block`) uses — one place for this mapping
/// rather than three copies of the same switch.
enum ContentOwnerRefColumns {
    static func encode(_ owner: ContentOwnerRef) -> (id: String, kind: String) {
        switch owner {
        case .meeting(let id): return (id.rawValue.uuidString, "meeting")
        case .brainDump(let id): return (id.rawValue.uuidString, "brainDump")
        case .note(let id): return (id.rawValue.uuidString, "note")
        }
    }

    static func decode(id: String, kind: String, table: String) throws -> ContentOwnerRef {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(table: table, column: "meeting_id", value: id)
        }
        switch kind {
        case "meeting": return .meeting(MeetingID(rawValue: uuid))
        case "brainDump": return .brainDump(BrainDumpID(rawValue: uuid))
        case "note": return .note(NoteID(rawValue: uuid))
        default:
            throw PersistenceError.corruptRow(table: table, column: "owner_kind", value: kind)
        }
    }
}
