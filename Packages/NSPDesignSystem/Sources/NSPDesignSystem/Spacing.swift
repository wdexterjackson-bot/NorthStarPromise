import CoreGraphics

/// The spacing scale every screen builds layout from (docs/07's own scope
/// note: this document specifies structure and states, not pixel values —
/// "those live in NSPDesignSystem tokens." A small fixed scale, not
/// arbitrary per-screen magic numbers.
public enum NSPSpacing {
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 24
    public static let extraExtraLarge: CGFloat = 32
}
