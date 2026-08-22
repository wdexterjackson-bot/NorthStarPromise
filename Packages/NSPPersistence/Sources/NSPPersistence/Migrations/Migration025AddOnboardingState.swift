import GRDB

/// Adds `policy.onboarding_state` and `policy.onboarding_last_step_index` —
/// "The First Hour" wizard's own progress tracking (2026-08-22). Defaults
/// match `OnboardingState.notStarted`/`0` so every pre-existing policy row
/// (including every fixture and every already-shipped workspace) resumes
/// as "hasn't started" rather than requiring a backfill.
enum Migration025AddOnboardingState: SchemaMigration {
    static let identifier = "025_addOnboardingState"

    static func up(_ db: Database) throws {
        try db.alter(table: "policy") { t in
            t.add(column: "onboarding_state", .text).notNull().defaults(to: "notStarted")
            t.add(column: "onboarding_last_step_index", .integer).notNull().defaults(to: 0)
        }
    }

    static func down(_ db: Database) throws {
        try db.alter(table: "policy") { t in
            t.drop(column: "onboarding_state")
            t.drop(column: "onboarding_last_step_index")
        }
    }
}
