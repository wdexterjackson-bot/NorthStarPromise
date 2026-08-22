import GRDB

/// Adds `meeting.color_slot`/`meeting.kind` and `scheduled_recording
/// .color_slot` — per-item rail color (`Palette.threadSlots`, indices
/// 0...5) chosen at creation by `AddAgendaItemFormView`'s color picker, and
/// the `.recorded`/`.notesOnly`/`.reminder` agenda-row type distinction
/// (docs/07's "Add to Today's Agenda" flow). `NOT NULL DEFAULT 0`/`'recorded'`
/// backfill every existing row to the neutral slot and the only kind that
/// existed before this column.
enum Migration017AddMeetingColorAndKind: SchemaMigration {
    static let identifier = "017_addMeetingColorSlotAndKind"

    static func up(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.add(column: "color_slot", .integer).notNull().defaults(to: 0)
            t.add(column: "kind", .text).notNull().defaults(to: "recorded")
        }
        try db.alter(table: "scheduled_recording") { t in
            t.add(column: "color_slot", .integer).notNull().defaults(to: 0)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.drop(column: "color_slot")
            t.drop(column: "kind")
        }
        try db.alter(table: "scheduled_recording") { t in
            t.drop(column: "color_slot")
        }
    }
}
