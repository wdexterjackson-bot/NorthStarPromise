import GRDB

/// Adds the Dashboard's commitment-ledger fields (`DASHBOARD_SPEC.md` §3.4)
/// onto the existing `action_item` and `decision` tables — extending both
/// rather than introducing a parallel `Commitment` table (Dashboard scope
/// plan's explicit default). All additive and defaulted, so every
/// already-sealed action/decision reads back with the "nothing extracted
/// yet, always trusted" defaults rather than needing a backfill.
enum Migration011AddCommitmentFields: SchemaMigration {
    static let identifier = "011_addCommitmentFields"

    static func up(_ db: Database) throws {
        try db.alter(table: "action_item") { t in
            t.add(column: "direction", .text).notNull().defaults(to: "iOwe")
            t.add(column: "defer_count", .integer).notNull().defaults(to: 0)
            t.add(column: "asked_again_count", .integer).notNull().defaults(to: 0)
            t.add(column: "confidence", .double).notNull().defaults(to: 1.0)
            t.add(column: "edited", .boolean).notNull().defaults(to: false)
        }
        try db.alter(table: "decision") { t in
            t.add(column: "defer_count", .integer).notNull().defaults(to: 0)
            t.add(column: "decide_by", .datetime)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "decision") { t in
            t.drop(column: "decide_by")
            t.drop(column: "defer_count")
        }
        try db.alter(table: "action_item") { t in
            t.drop(column: "edited")
            t.drop(column: "confidence")
            t.drop(column: "asked_again_count")
            t.drop(column: "defer_count")
            t.drop(column: "direction")
        }
    }
}
