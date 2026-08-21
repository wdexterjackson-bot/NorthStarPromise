import SwiftUI

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// The Dashboard spec's exact light/dark hex pairs (`DASHBOARD_SPEC.md` §2.2)
/// — a real, designed palette, distinct from `NSPColor`'s system-color
/// routing. Both coexist deliberately during the app-wide migration
/// (CLAUDE.md §5's "no half-finished implementations" is about behavior,
/// not about a visual system landing screen-by-screen): `NSPColor` remains
/// correct for anything not yet migrated, `Palette` is what every new or
/// re-skinned screen should reach for.
///
/// This is the Dashboard's own palette — iPhone/iPad only (`DASHBOARD_SPEC.md`
/// is scoped to those two platforms). watchOS links `NSPDesignSystem` too
/// (it's a shared dependency), but `UIColor`'s dynamic-provider API and
/// `UITraitCollection.userInterfaceStyle` aren't available there, so this
/// resolves to a fixed dark value on watch rather than reacting to
/// appearance — nothing on the Watch app reads `Palette` today.
extension Color {
    /// Resolves per `UITraitCollection.userInterfaceStyle`/`NSAppearance`
    /// rather than `colorScheme` from the environment — this must work in
    /// contexts (`#Preview`-style static previews, non-view call sites) that
    /// don't carry a SwiftUI environment.
    public static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS) || os(tvOS)
            Color(
                uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
                })
        #elseif os(macOS)
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(rgb: dark) : NSColor(rgb: light)
                })
        #else
            Color(rgbHex: dark)
        #endif
    }
}

#if os(iOS) || os(tvOS)
    extension UIColor {
        fileprivate convenience init(rgb: UInt32) {
            self.init(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
        }
    }
#elseif os(macOS)
    extension NSColor {
        fileprivate convenience init(rgb: UInt32) {
            self.init(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
        }
    }
#else
    extension Color {
        fileprivate init(rgbHex rgb: UInt32) {
            self.init(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255)
        }
    }
#endif

/// Foreground / tint-background / tint-border triple for a semantic color —
/// the shape every `accent`/`warn`/`danger`/`success` role takes wherever it
/// appears tinted (`StatusChip`, `TintedIconTile`, signal cards).
public struct SemanticTint: Sendable {
    public let foreground: Color
    public let background: Color
    public let border: Color

    public init(foreground: Color, background: Color, border: Color) {
        self.foreground = foreground
        self.background = background
        self.border = border
    }
}

/// Design-system color tokens per `DASHBOARD_SPEC.md` §2.2. Every token is a
/// light/dark pair resolved dynamically — never hard-coded to a device or
/// theme (the spec's own §2.1 rule: iPhone-dark/iPad-light in the mockups is
/// a presentation choice, not a platform rule).
public enum Palette {
    // Surfaces & structure
    public static let canvas = Color.dynamic(light: 0xF4_F5F7, dark: 0x0A_0B0D)
    public static let surface = Color.dynamic(light: 0xFF_FFFF, dark: 0x13_1519)
    public static let surfaceSunken = Color.dynamic(light: 0xFB_FBFC, dark: 0x0F_1116)
    public static let chrome = Color.dynamic(light: 0xFF_FFFF, dark: 0x0E_1014)
    public static let fill = Color.dynamic(light: 0xF2_F4F7, dark: 0x1C_2027)
    public static let border = Color.dynamic(light: 0xE4_E7EC, dark: 0x23_272E)
    public static let borderStrong = Color.dynamic(light: 0xD6_DAE1, dark: 0x2A_2F38)
    public static let divider = Color.dynamic(light: 0xEA_ECF0, dark: 0x1E_222A)

    // Text
    public static let textPrimary = Color.dynamic(light: 0x14_161B, dark: 0xF0_F2F5)
    public static let textSecondary = Color.dynamic(light: 0x47_5467, dark: 0xB7_BFCA)
    public static let textTertiary = Color.dynamic(light: 0x66_7085, dark: 0x8B_93A0)
    public static let textQuaternary = Color.dynamic(light: 0x98_A2B3, dark: 0x61_6977)
    public static let textMuted = Color.dynamic(light: 0xB6_BDC9, dark: 0x4E_5561)

    // Reserved for the capture control and the agenda now-marker only —
    // see `record`'s own doc comment below.
    public static let record = Color.dynamic(light: 0xF0_4A44, dark: 0xFF_5B54)
    public static let recordDark = Color.dynamic(light: 0xD6_2F29, dark: 0xE8_342E)
    public static let nowMarker = Color.dynamic(light: 0xE8_342E, dark: 0xFF_4A45)

    /// Reserved for the Brain Dump / Mental Note control only — deliberately
    /// its own token rather than a reference to `threadSlots[4]` (violet),
    /// even though the values match today. A thread's slot color is
    /// arbitrary identity (`threadSlots`' own doc comment); this one has a
    /// fixed, specific meaning, and the two must never be read as the same
    /// thing just because they render the same hex.
    public static let brainDump = Color.dynamic(light: 0x7B_3FD1, dark: 0xA4_6BE0)

    /// The full `SemanticTint` around `brainDump` — for spots (Library's
    /// `TintedIconTile`, a future badge) that need the matching background/
    /// border pair `StatusChip`-style tints already get, not just the bare
    /// foreground color above.
    public static let brainDumpTint = SemanticTint(
        foreground: brainDump,
        background: Color.dynamic(light: 0xF3_ECFC, dark: 0x27_1F38),
        border: Color.dynamic(light: 0xE1_D2F7, dark: 0x3D_305A))

    public static let accent = SemanticTint(
        foreground: Color.dynamic(light: 0x2F_6FE4, dark: 0x5B_8DEF),
        background: Color.dynamic(light: 0xEC_F2FE, dark: 0x1A_2740),
        border: Color.dynamic(light: 0xD5_E2FB, dark: 0x2C_3F5E))

    public static let warn = SemanticTint(
        foreground: Color.dynamic(light: 0x8A_5310, dark: 0xE5_A244),
        background: Color.dynamic(light: 0xFD_F3E3, dark: 0x2E_2413),
        border: Color.dynamic(light: 0xF3_DFBB, dark: 0x4A_381C))

    public static let danger = SemanticTint(
        foreground: Color.dynamic(light: 0xB4_2318, dark: 0xFF_6B66),
        background: Color.dynamic(light: 0xFE_ECEA, dark: 0x30_1A18),
        border: Color.dynamic(light: 0xF8_D3CE, dark: 0x4A_2624))

    public static let success = SemanticTint(
        foreground: Color.dynamic(light: 0x12_805C, dark: 0x3F_BF8F),
        background: Color.dynamic(light: 0xE9_F6F1, dark: 0x12_2A22),
        border: Color.dynamic(light: 0xC9_E8DD, dark: 0x1E_3F32))

    /// A completed or dormant thread's rail/dot color — never one of the six
    /// slots below, so a glance at color alone tells "still moving" from
    /// "not anymore" (paired with the thread name in text regardless,
    /// per the spec's own accessibility rule that color is never the sole
    /// carrier of meaning).
    public static let threadInactive = Color.dynamic(light: 0xD6_D9E0, dark: 0x3A_4250)

    /// The six-slot categorical ramp threads are assigned from at creation
    /// (`stableHash(thread.id) % 6`) and keep for life — see
    /// `ThreadColorSlot` in `NSPCore`.
    public static let threadSlots: [Color] = [
        Color.dynamic(light: 0x4C_58E0, dark: 0x6E_7BFF),  // 1 indigo
        Color.dynamic(light: 0x12_8577, dark: 0x2F_B6A8),  // 2 teal
        Color.dynamic(light: 0xA6_6412, dark: 0xD9_A03C),  // 3 amber
        Color.dynamic(light: 0xC1_476A, dark: 0xE0_607E),  // 4 rose
        Color.dynamic(light: 0x7B_3FD1, dark: 0xA4_6BE0),  // 5 violet
        Color.dynamic(light: 0x2F_6FE4, dark: 0x5B_8DEF),  // 6 blue
    ]
}
