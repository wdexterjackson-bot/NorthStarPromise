/// An action item's lifecycle (docs/02 §2). Cannot reach `.sent` without
/// evidence and explicit human confirmation of the payload (Invariant I6).
public enum ActionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case proposed
    case confirmed
    case sent
    case inProgress
    case done
    case dismissed
}

/// A decision's lifecycle (docs/02 §2). `.superseded` decisions keep their
/// evidence and point at the decision that replaced them.
public enum DecisionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case proposed
    case approved
    case superseded
}
