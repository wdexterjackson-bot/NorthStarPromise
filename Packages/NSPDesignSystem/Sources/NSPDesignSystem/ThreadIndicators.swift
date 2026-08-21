import SwiftUI

/// The universal "this belongs to a storyline" marker (`DASHBOARD_SPEC.md`
/// §2.6, §2.2's thread color ramp) — a thin capsule rail in the thread's
/// color, used in the agenda and thread list. Domain-agnostic: callers pass
/// the resolved `Color` (`Palette.threadSlots[thread.colorSlot]` or
/// `Palette.threadInactive`), not a `Thread` value.
public struct ThreadRail: View {
    public let color: Color
    public let height: CGFloat

    public init(color: Color, height: CGFloat = 26) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: 3, height: height)
            .accessibilityHidden(true)
    }
}

/// A lighter-weight thread marker for contexts a rail is too heavy for (card
/// headers, timeline nodes). The *current* meeting's dot carries a soft halo
/// of the same color — `isCurrent` drives that, per spec §2.6/§5.4.
public struct ThreadDot: View {
    public let color: Color
    public let isCurrent: Bool
    public let size: CGFloat

    public init(color: Color, isCurrent: Bool = false, size: CGFloat = 8) {
        self.color = color
        self.isCurrent = isCurrent
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if isCurrent {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: size + 6, height: size + 6)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: NSPSpacing.large) {
        HStack(spacing: NSPSpacing.medium) {
            ThreadRail(color: Palette.threadSlots[0])
            ThreadRail(color: Palette.threadSlots[3])
            ThreadRail(color: Palette.threadInactive)
        }
        HStack(spacing: NSPSpacing.medium) {
            ThreadDot(color: Palette.threadSlots[1])
            ThreadDot(color: Palette.threadSlots[4], isCurrent: true)
        }
    }
    .padding()
    .background(Palette.canvas)
}
