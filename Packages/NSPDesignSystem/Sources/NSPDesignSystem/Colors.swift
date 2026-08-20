import SwiftUI

/// Semantic color tokens. docs/07's own scope note says no palette lives in
/// the UX spec — these route through system colors (adaptive to Dynamic
/// Type, Dark Mode, and increased-contrast automatically) rather than
/// inventing hex values nobody has designed yet. A future visual design
/// pass replaces the right-hand side of these, never the call sites.
///
/// Platform-conditional because the true system-background/-grouping
/// colors are `UIKit`/`AppKit` types with no shared cross-platform API —
/// this package still declares `.macOS` and `.watchOS` (for `swift test`
/// and future Watch UI), so every branch needs to resolve to something
/// real on that platform, not just iOS.
public enum NSPColor {
    #if os(iOS) || os(tvOS)
        public static let background = Color(uiColor: .systemGroupedBackground)
        public static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        /// A raised card surface on top of `background` — distinct from
        /// `secondaryBackground` so a card still reads as "raised" even when
        /// `background` itself is a grouped (non-white) system color.
        public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    #elseif os(macOS)
        public static let background = Color(nsColor: .windowBackgroundColor)
        public static let secondaryBackground = Color(nsColor: .underPageBackgroundColor)
        public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #else
        public static let background = Color.black
        public static let secondaryBackground = Color.gray
        public static let cardBackground = Color.gray
    #endif

    public static let primaryText = Color.primary
    public static let secondaryText = Color.secondary
    public static let accent = Color.accentColor

    // Status colors are never the *only* signal (docs/07 §10: "status
    // never colour-only") — always paired with an SF Symbol and/or text
    // label at the call site, e.g. `NSPStatusBadge`.
    public static let statusNeutral = Color.secondary
    public static let statusSuccess = Color.green
    public static let statusWarning = Color.orange
    public static let statusDanger = Color.red
    public static let statusInProgress = Color.blue
}
