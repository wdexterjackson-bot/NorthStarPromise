import SwiftUI

/// A 26–28pt tinted rounded-square icon tile (`DASHBOARD_SPEC.md` §2.6) —
/// the prep-row / signal-row icon, distinct from `NSPIconBadge`'s bolder
/// gradient-filled tile: this one is a soft 10–11% tint with a matching
/// hairline border, matching the Dashboard's flat, borders-not-shadows
/// elevation rule (spec §2.4).
public struct TintedIconTile: View {
    public let symbolName: String
    public let tint: SemanticTint
    public let size: CGFloat

    public init(symbolName: String, tint: SemanticTint, size: CGFloat = 26) {
        self.symbolName = symbolName
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Metrics.radiusIconChip, style: .continuous)
            .fill(tint.foreground.opacity(0.11))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusIconChip, style: .continuous)
                    .strokeBorder(tint.foreground.opacity(0.24), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(tint.foreground)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: NSPSpacing.medium) {
        TintedIconTile(symbolName: "clock", tint: Palette.warn)
        TintedIconTile(symbolName: "arrow.uturn.left", tint: Palette.accent)
        TintedIconTile(symbolName: "smallcircle.filled.circle", tint: Palette.success)
    }
    .padding()
    .background(Palette.canvas)
}
