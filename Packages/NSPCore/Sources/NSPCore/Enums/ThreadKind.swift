/// What kind of storyline an `NSPThread` tracks (`DASHBOARD_SPEC.md` §3.2)
/// — purely descriptive, shown as context on the thread card; nothing in
/// this pass branches behavior on it.
public enum ThreadKind: String, Sendable, Hashable, Codable, CaseIterable {
    case account
    case deal
    case initiative
    case recurring
    case oneOnOne
}
