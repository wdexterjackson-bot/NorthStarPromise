import SwiftUI

/// A raised card surface — `NSPColor.cardBackground`, rounded corners, and a
/// soft shadow. The one visual container this app's screens build list/grid
/// content on top of, so cards read consistently everywhere rather than
/// each screen inventing its own padding/corner radius.
public struct NSPCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(NSPSpacing.large)
            .background(NSPColor.cardBackground, in: .rect(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

extension View {
    public func nspCard() -> some View {
        modifier(NSPCardModifier())
    }
}
