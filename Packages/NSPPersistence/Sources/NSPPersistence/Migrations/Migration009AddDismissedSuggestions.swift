import GRDB

/// Adds `dismissed_thread_suggestion` — remembers which system-suggested
/// thread groupings (`ThreadSuggestionEngine.SuggestedThread.fingerprint`)
/// the user has already dismissed, so they don't reappear every time
/// `ThreadsListView` recomputes suggestions.
enum Migration009AddDismissedSuggestions: SchemaMigration {
    static let identifier = "009_addDismissedThreadSuggestions"

    static func up(_ db: Database) throws {
        try db.create(table: "dismissed_thread_suggestion") { t in
            t.primaryKey("fingerprint", .text)
            t.column("workspace_id", .text).notNull().references("workspace", onDelete: .cascade)
            t.column("dismissed_at", .datetime).notNull()
        }
    }

    static func down(_ db: Database) throws {
        try db.drop(table: "dismissed_thread_suggestion")
    }
}
