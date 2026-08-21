import CoreGraphics

/// The Dashboard spec's 4pt-based spacing/radius scale (`DASHBOARD_SPEC.md`
/// §2.4) — additive to `NSPSpacing`, not a replacement. `NSPSpacing` stays
/// correct for screens not yet migrated to `Palette`/`Typo`; new and
/// re-skinned screens use `Metrics` for anything the spec gives an exact
/// value for.
public enum Metrics {
    // Horizontal insets
    public static let screenMarginPhone: CGFloat = 20
    public static let screenMarginPadMain: CGFloat = 28
    public static let screenMarginPadSidebar: CGFloat = 18

    // Between Dashboard sections / inside cards / between elements
    public static let sectionGap: CGFloat = 18
    public static let cardPaddingPhone: CGFloat = 15
    public static let cardPaddingPadHeroH: CGFloat = 24
    public static let cardPaddingPadHeroV: CGFloat = 22
    public static let cardPaddingPad: CGFloat = 16
    public static let stackGap: CGFloat = 11
    public static let rowGap: CGFloat = 5
    public static let iconGap: CGFloat = 9

    // Radii
    public static let radiusHeroPhone: CGFloat = 18
    public static let radiusHeroPad: CGFloat = 20
    public static let radiusCard: CGFloat = 16
    public static let radiusControl: CGFloat = 12
    public static let radiusIconChip: CGFloat = 9
    public static let radiusChip: CGFloat = 6
    public static let radiusPill: CGFloat = 9999
}
