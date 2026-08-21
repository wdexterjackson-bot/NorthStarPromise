import SwiftUI

/// One participant's avatar chip inside an `AvatarStack` — initials on a
/// muted, desaturated color derived from a stable hash of the person's id
/// (`DASHBOARD_SPEC.md` §2.6: "never the semantic palette").
public struct AvatarRef: Identifiable, Hashable, Sendable {
    public let id: String
    public let initials: String

    public init(id: String, initials: String) {
        self.id = id
        self.initials = initials
    }

    fileprivate var color: Color {
        var hasher = Hasher()
        hasher.combine(id)
        let hue = Double(abs(hasher.finalize()) % 360) / 360
        return Color(hue: hue, saturation: 0.28, brightness: 0.62)
    }
}

/// Overlapping avatar circles with a `+N` overflow chip
/// (`DASHBOARD_SPEC.md` §2.6) — used on the Next Up card and agenda rows.
public struct AvatarStack: View {
    public let people: [AvatarRef]
    public let size: CGFloat
    public let maxShown: Int

    public init(_ people: [AvatarRef], size: CGFloat = 21, maxShown: Int = 3) {
        self.people = people
        self.size = size
        self.maxShown = maxShown
    }

    public var body: some View {
        HStack(spacing: -7) {
            ForEach(people.prefix(maxShown)) { person in
                Circle()
                    .fill(person.color)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(person.initials)
                            .font(Typo.ui(size * 0.4, .extrabold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 1.5))
            }
            if people.count > maxShown {
                Circle()
                    .fill(Palette.fill)
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(people.count - maxShown)")
                            .font(Typo.ui(size * 0.38, .bold))
                            .foregroundStyle(Palette.textSecondary)
                    )
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people.map(\.initials).joined(separator: ", "))
    }
}

#Preview {
    AvatarStack([
        AvatarRef(id: "1", initials: "JD"),
        AvatarRef(id: "2", initials: "RM"),
        AvatarRef(id: "3", initials: "PK"),
        AvatarRef(id: "4", initials: "TL"),
    ])
    .padding()
    .background(Palette.canvas)
}
