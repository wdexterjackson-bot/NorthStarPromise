/// A field that may be stated outright, inferred by AI (and so visibly
/// labelled), or missing. Used for `Action.owner`/`Action.date`
/// (docs/02 §2: "unresolved owner/date are visibly labelled as inferred or
/// absent"). Ambiguity here blocks an automated external write (Invariant I6).
public enum ResolvedValue<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    case explicit(Value)
    case inferred(Value)
    case unresolved
}
