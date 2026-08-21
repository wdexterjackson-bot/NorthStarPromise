import SwiftUI

/// The app's most repeated atom (`DASHBOARD_SPEC.md` §2.6): a tinted,
/// uppercase status label that never wraps and never shrinks — used for
/// "Recap ready", "Decision due", "At risk", "3 open", and every other
/// short status word across Threads/Actions/Library. Domain-agnostic, same
/// convention as `NSPStatusBadge`: callers map their own domain enum to a
/// `StatusChip.Style` at the call site.
public struct StatusChip: View {
    public enum Style: Sendable {
        case success, warn, danger, neutral

        var tint: SemanticTint {
            switch self {
            case .success: return Palette.success
            case .warn: return Palette.warn
            case .danger: return Palette.danger
            case .neutral:
                return SemanticTint(
                    foreground: Palette.textSecondary, background: Palette.fill, border: Palette.border)
            }
        }
    }

    public let label: String
    public let style: Style

    public init(_ label: String, style: Style) {
        self.label = label
        self.style = style
    }

    public var body: some View {
        Text(label.uppercased())
            .font(Typo.ui(9.5, .extrabold, relativeTo: .caption2))
            .tracking(0.05 * 9.5)
            .foregroundStyle(style.tint.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(style.tint.background, in: .rect(cornerRadius: Metrics.radiusChip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusChip, style: .continuous)
                    .strokeBorder(style.tint.border, lineWidth: 1)
            )
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: NSPSpacing.small) {
        StatusChip("Recap ready", style: .success)
        StatusChip("Decision due", style: .warn)
        StatusChip("At risk", style: .danger)
        StatusChip("3 open", style: .neutral)
    }
    .padding()
    .background(Palette.canvas)
}
