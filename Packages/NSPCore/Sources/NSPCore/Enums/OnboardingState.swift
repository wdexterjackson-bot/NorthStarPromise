/// Where a workspace stands with the "Getting Started" wizard ("The First
/// Hour" recommendation, 2026-08-22) — whether the human assistant-style
/// setup flow has run, been skipped, or is sitting mid-way. Lives on
/// `Policy` (workspace-scoped, same reasoning `ambientModeEnabled` already
/// uses) rather than on `Person`, since it describes the workspace's setup
/// progress, not any one person.
public enum OnboardingState: String, Sendable, Hashable, Codable, CaseIterable {
    case notStarted
    case inProgress
    /// The user explicitly chose "Skip for now" — distinct from
    /// `.notStarted` so `RootView` never auto-presents the wizard a second
    /// time uninvited; reachable again only from Settings.
    case skipped
    case completed

    /// `RootView` auto-presents the wizard exactly once, only from this
    /// state — `.skipped`/`.inProgress`/`.completed` are all reachable
    /// again only through an explicit Settings tap, never automatically.
    public var shouldAutoPresent: Bool { self == .notStarted }

    /// Whether re-entering the wizard resumes an old session (`.inProgress`)
    /// or starts a brand-new one — `.skipped`/`.completed` both restart
    /// from step 0 rather than replaying stale answers, since the user is
    /// choosing "Redo"/"Get Started" again deliberately.
    public var resumesExistingSession: Bool { self == .inProgress }
}
