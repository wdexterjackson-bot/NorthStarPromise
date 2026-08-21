/// Which way an `Action` obligation runs (`DASHBOARD_SPEC.md` §3.4's
/// `Commitment.direction`) — extended onto `Action` rather than a parallel
/// `Commitment` type (Dashboard scope plan's explicit default: one ledger,
/// not two competing ones).
public enum CommitmentDirection: String, Sendable, Hashable, Codable, CaseIterable {
    /// The user owes the counterparty this.
    case iOwe
    /// The counterparty owes the user this.
    case theyOwe
}
