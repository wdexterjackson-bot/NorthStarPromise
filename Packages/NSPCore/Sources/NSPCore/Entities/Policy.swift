/// A frozen policy snapshot in force for one meeting or workspace
/// (docs/02 §2, "Supporting entities"; docs/06). `NSPPolicy` is the only
/// module permitted to construct or evaluate one at runtime.
public struct Policy: Sendable, Hashable, Codable, Identifiable {
    public let policyID: PolicyID
    public var id: PolicyID { policyID }
    public let workspaceID: WorkspaceID

    public var retentionDays: Int?
    public var defaultProcessingMode: ProcessingMode
    public var announcementRequired: Bool
    public var blockedDomains: [String]
    public var blockedLocations: [String]

    /// Ambient Mode fields (added 2026-08-22, "Overheard" recommendation).
    /// Default off. `ambientTrustedLocations` mirrors `blockedLocations`'s
    /// own shape exactly — a plain, user-typed location-label list, not
    /// backed by real geofencing (no `CoreLocation` integration exists in
    /// this codebase for either field yet; this is a data placeholder,
    /// same as `blockedLocations` already is, not a claim of enforcement).
    /// `ambientModeEnabled` is the workspace's standing permission to use
    /// the feature at all (surfaced in the onboarding disclosure and a
    /// Settings toggle) — a live session's own on/off state is transient,
    /// owned by `AmbientCoordinator`, and never persisted here.
    public var ambientModeEnabled: Bool
    public var ambientTrustedLocations: [String]
    /// 30–150 minutes, 30-minute steps — the Settings picker's range.
    /// Reaching this limit prompts "Continue Ambient Mode?" rather than
    /// silently stopping or silently continuing.
    public var ambientSessionDurationMinutes: Int

    /// "The First Hour" wizard's own progress (2026-08-22) — see
    /// `OnboardingState`'s own doc comment for the state machine this
    /// drives. Workspace-scoped, like every other `Policy` field.
    public var onboardingState: OnboardingState
    /// Which wizard step to resume on — only meaningful while
    /// `onboardingState == .inProgress`; ignored otherwise. `0`-indexed,
    /// matching `GettingStartedCoordinator.Step.allCases`' own ordering.
    public var onboardingLastStepIndex: Int

    public init(
        policyID: PolicyID,
        workspaceID: WorkspaceID,
        retentionDays: Int? = nil,
        defaultProcessingMode: ProcessingMode,
        announcementRequired: Bool = false,
        blockedDomains: [String] = [],
        blockedLocations: [String] = [],
        ambientModeEnabled: Bool = false,
        ambientTrustedLocations: [String] = [],
        ambientSessionDurationMinutes: Int = 60,
        onboardingState: OnboardingState = .notStarted,
        onboardingLastStepIndex: Int = 0
    ) {
        self.policyID = policyID
        self.workspaceID = workspaceID
        self.retentionDays = retentionDays
        self.defaultProcessingMode = defaultProcessingMode
        self.announcementRequired = announcementRequired
        self.blockedDomains = blockedDomains
        self.blockedLocations = blockedLocations
        self.ambientModeEnabled = ambientModeEnabled
        self.ambientTrustedLocations = ambientTrustedLocations
        self.ambientSessionDurationMinutes = ambientSessionDurationMinutes
        self.onboardingState = onboardingState
        self.onboardingLastStepIndex = onboardingLastStepIndex
    }
}
