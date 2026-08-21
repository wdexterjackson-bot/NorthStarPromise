import SwiftUI

/// The Dashboard's inverted primary action (`DASHBOARD_SPEC.md` §2.6):
/// `textPrimary`-filled background with a `canvas`-colored label — the
/// opposite of `.buttonStyle(.borderedProminent)`'s accent fill, chosen so
/// the capture control's red stays the only saturated color competing for
/// attention on the screen (spec §2.2's "record is reserved" rule).
public struct PrimaryButton: View {
    public let title: String
    public let symbolName: String?
    public let action: () -> Void

    public init(_ title: String, symbolName: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbolName {
                    Image(systemName: symbolName).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(Typo.ui(13.5, .bold))
            }
            .foregroundStyle(Palette.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Palette.textPrimary, in: .rect(cornerRadius: Metrics.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The Dashboard's secondary action — `surface` fill with a `borderStrong`
/// outline, per `DASHBOARD_SPEC.md` §2.6.
public struct SecondaryButton: View {
    public let title: String
    public let symbolName: String?
    public let action: () -> Void

    public init(_ title: String, symbolName: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbolName {
                    Image(systemName: symbolName).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(Typo.ui(13.5, .bold))
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(height: 44)
            .padding(.horizontal, NSPSpacing.large)
            .background(Palette.surface, in: .rect(cornerRadius: Metrics.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: NSPSpacing.medium) {
        PrimaryButton("Open the brief", symbolName: "doc.text") {}
        SecondaryButton("Join", symbolName: "video") {}
    }
    .padding()
    .background(Palette.canvas)
}
