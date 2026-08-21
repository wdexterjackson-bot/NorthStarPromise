import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Whether a named font is actually registered on this build — real files
/// live at `App/Phone/Resources/Fonts` and are registered via `project.yml`'s
/// `UIAppFonts`, but `Typo` must still degrade gracefully (rather than
/// silently rendering the system font with no visual explanation) on any
/// target that hasn't picked up the registration, e.g. a package `#Preview`
/// with no app bundle behind it.
private func isFontAvailable(_ name: String) -> Bool {
    #if canImport(UIKit)
        UIFont(name: name, size: 12) != nil
    #elseif canImport(AppKit)
        NSFont(name: name, size: 12) != nil
    #else
        false
    #endif
}

/// Manrope's five UI weights (`DASHBOARD_SPEC.md` §2.3) with their real
/// PostScript names, plus each one's fallback stop in the Avenir Next chain
/// the spec documents.
public enum ManropeWeight: Sendable {
    case regular, medium, semibold, bold, extrabold

    var postScriptName: String {
        switch self {
        case .regular: return "Manrope-Regular"
        case .medium: return "Manrope-Medium"
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        case .extrabold: return "Manrope-ExtraBold"
        }
    }

    fileprivate var avenirNextFallback: String {
        switch self {
        case .regular: return "AvenirNext-Regular"
        case .medium: return "AvenirNext-Medium"
        case .semibold: return "AvenirNext-DemiBold"
        case .bold: return "AvenirNext-Bold"
        case .extrabold: return "AvenirNext-Heavy"
        }
    }

    fileprivate var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .extrabold: return .heavy
        }
    }
}

/// The app's two-typeface system (`DASHBOARD_SPEC.md` §2.3). `display` is
/// Instrument Serif, reserved for exactly one screen-title word per screen —
/// never a card title, never a number, never italic (the spec's own rule).
/// `ui` is Manrope for everything else. Both resolve through the spec's
/// documented fallback stack when the named font isn't registered, so this
/// code needed no changes once the real font files landed.
public enum Typo {
    public static func display(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        if isFontAvailable("InstrumentSerif-Regular") {
            return .custom("InstrumentSerif-Regular", size: size, relativeTo: textStyle)
        }
        for name in ["Iowan Old Style", "Palatino", "Georgia"] where isFontAvailable(name) {
            return .custom(name, size: size, relativeTo: textStyle)
        }
        return .system(size: size, design: .serif)
    }

    public static func ui(
        _ size: CGFloat, _ weight: ManropeWeight, relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        if isFontAvailable(weight.postScriptName) {
            return .custom(weight.postScriptName, size: size, relativeTo: textStyle)
        }
        if isFontAvailable(weight.avenirNextFallback) {
            return .custom(weight.avenirNextFallback, size: size, relativeTo: textStyle)
        }
        return .system(size: size, weight: weight.systemWeight, design: .default)
    }
}
