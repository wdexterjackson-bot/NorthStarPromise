import SwiftUI

/// A colored rounded-square icon tile — the Settings-app/Reminders-app
/// pattern for giving a list row a recognizable glyph instead of a plain
/// monochrome SF Symbol. Domain-agnostic, same reasoning as
/// `NSPStatusBadge`: callers map their own domain type to a symbol/tint.
public struct NSPIconBadge: View {
    public let symbolName: String
    public let tint: Color
    public let size: CGFloat

    public init(symbolName: String, tint: Color, size: CGFloat = 30) {
        self.symbolName = symbolName
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: NSPSpacing.medium) {
        NSPIconBadge(symbolName: "mic.fill", tint: .red)
        NSPIconBadge(symbolName: "checkmark.circle.fill", tint: .green)
        NSPIconBadge(symbolName: "gearshape.fill", tint: .gray)
    }
    .padding()
}
