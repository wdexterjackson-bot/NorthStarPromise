/// What kind of storyline an `NSPThread` tracks (`DASHBOARD_SPEC.md` §3.2)
/// — purely descriptive, shown as context on the thread card; nothing in
/// this pass branches behavior on it.
public enum ThreadKind: String, Sendable, Hashable, Codable, CaseIterable {
    case account
    case deal
    case initiative
    case recurring
    case oneOnOne
    /// A family/home storyline — added 2026-08-22 for Ambient Mode's
    /// household use case ("Overheard" recommendation, Phase 2), so a
    /// family's ambient suggestions land somewhere distinct from work
    /// threads on My Work rather than mixing into a work Dashboard.
    case household
}
