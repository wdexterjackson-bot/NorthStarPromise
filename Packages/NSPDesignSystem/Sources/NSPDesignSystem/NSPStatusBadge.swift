import SwiftUI

/// A status indicator that is never color-only (docs/07 §10, an
/// accessibility rule the UX spec states as normative): every badge pairs
/// an SF Symbol and a text label with its tint, so color blindness or
/// grayscale display never loses the information.
///
/// Deliberately domain-agnostic — it takes a symbol/label/tint, not a
/// `MeetingState` or `Availability`. Mapping a domain enum to those three
/// values is presentation logic that belongs where the domain type is
/// used, not in the design system (`NSPDesignSystem` has no reason to know
/// what `MeetingState` is).
public struct NSPStatusBadge: View {
    public let symbolName: String
    public let label: String
    public let tint: Color

    public init(symbolName: String, label: String, tint: Color) {
        self.symbolName = symbolName
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        Label(label, systemImage: symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: NSPSpacing.small) {
        NSPStatusBadge(symbolName: "checkmark.circle.fill", label: "Complete", tint: NSPColor.statusSuccess)
        NSPStatusBadge(symbolName: "exclamationmark.triangle.fill", label: "Needs review", tint: NSPColor.statusWarning)
        NSPStatusBadge(symbolName: "xmark.circle.fill", label: "Failed", tint: NSPColor.statusDanger)
        NSPStatusBadge(symbolName: "circle.dotted", label: "Processing", tint: NSPColor.statusInProgress)
    }
    .padding()
}
