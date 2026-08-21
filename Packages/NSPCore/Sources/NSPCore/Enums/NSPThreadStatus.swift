/// An `NSPThread`'s lifecycle (`DASHBOARD_SPEC.md` §3.2) — replaces the
/// former `ThreadInMotionStatus`'s `active/completed/archived` with the
/// spec's richer, derivable set. `closed` is the one case a human sets
/// directly; the other four are recomputed from real data by
/// `ThreadStatusDeriver` wherever a thread's actions/decisions are already
/// loaded (ticket-scoped deferral of the full nightly signals engine —
/// see the Dashboard scope plan's "Deferred" section).
public enum NSPThreadStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case onTrack
    case decisionDue
    case atRisk
    case dormant
    case closed
}
