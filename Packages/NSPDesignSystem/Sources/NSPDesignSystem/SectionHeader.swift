import SwiftUI

/// The Dashboard's section-title row (`DASHBOARD_SPEC.md` §2.6): an
/// uppercase `sectionLabel` on the left, an optional inline `StatusChip`,
/// and an optional trailing accent-colored action ("All 14", "Agenda").
public struct SectionHeader: View {
    public let title: String
    public let inlineChip: (label: String, style: StatusChip.Style)?
    public let trailingAction: (label: String, action: () -> Void)?

    public init(
        _ title: String,
        inlineChip: (label: String, style: StatusChip.Style)? = nil,
        trailingAction: (label: String, action: () -> Void)? = nil
    ) {
        self.title = title
        self.inlineChip = inlineChip
        self.trailingAction = trailingAction
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NSPSpacing.small) {
            Text(title.uppercased())
                .font(Typo.ui(10, .extrabold, relativeTo: .caption2))
                .tracking(0.14 * 10)
                .foregroundStyle(Palette.textQuaternary)
            if let inlineChip {
                StatusChip(inlineChip.label, style: inlineChip.style)
            }
            Spacer(minLength: 0)
            if let trailingAction {
                Button(trailingAction.label, action: trailingAction.action)
                    .font(Typo.ui(11, .bold))
                    .foregroundStyle(Palette.accent.foreground)
                    .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: NSPSpacing.large) {
        SectionHeader("Threads in motion", trailingAction: ("All 14", {}))
        SectionHeader("Needs you", inlineChip: ("1 overdue", .danger), trailingAction: ("4 open", {}))
    }
    .padding()
    .background(Palette.canvas)
}
