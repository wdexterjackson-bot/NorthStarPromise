import GRDB

/// Adds `meeting.subtitle` — iPad's ruled-paper canvas title band gained a
/// second line (docs/07 §5's mockup) with no existing column to hold it.
/// Additive and nullable, so every already-sealed meeting reads back with
/// `subtitle == nil` rather than needing a backfill.
enum Migration002AddMeetingSubtitle: SchemaMigration {
    static let identifier = "002_addMeetingSubtitle"

    static func up(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.add(column: "subtitle", .text)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "meeting") { t in
            t.drop(column: "subtitle")
        }
    }
}
