import SwiftUI

// MARK: - Hex color support

extension Color {
    /// Create a Color from a hex string like "#456b47" or "456b47".
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        switch s.count {
        case 8: // RRGGBBAA
            r = Double((rgb >> 24) & 0xFF) / 255
            g = Double((rgb >> 16) & 0xFF) / 255
            b = Double((rgb >> 8) & 0xFF) / 255
            a = Double(rgb & 0xFF) / 255
        default: // RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Same color at a given opacity.
    func at(_ opacity: Double) -> Color { self.opacity(opacity) }
}

// MARK: - Design tokens — glassmorphic botanical green
//
// Chrome and surfaces live in a cool botanical palette (deep forest primary,
// mint-glass cards on a pale leaf gradient). The mood scale keeps its clinical
// calm→intense ramp, and crisis actions keep a distinct warm urgent color so
// they can never be confused with everyday UI.

enum Token {
    // Backgrounds (pale leaf gradient stops)
    static let screenBG       = Color(hex: "eef3e9")
    static let safetyBG       = Color(hex: "f1f0e4")
    static let shellTop       = Color(hex: "f3f7ee")
    static let shellMid       = Color(hex: "e7efdf")
    static let shellBottom    = Color(hex: "d9e5cf")

    // Surfaces — translucent whites over the gradient read as frosted glass
    static let cardSurface    = Color.white.opacity(0.74)
    static let sageCard       = Color(hex: "e4ecdc")
    static let warmAlertCard  = Color(hex: "f2ecd9")
    static let iconTileSage   = Color(hex: "e4ecdc")
    static let backButtonBG   = Color.white.opacity(0.62)
    static let moodEmpty      = Color(hex: "eef0e5")

    // Borders
    static let borderCard     = Color(hex: "dce6d1")
    static let borderChip     = Color(hex: "d3e0c7")
    static let borderOutline  = Color(hex: "bfd2b3")
    static let borderSage     = Color(hex: "cddcc0")
    static let borderWarm     = Color(hex: "e0d3ae")

    // Botanical green family
    static let primary        = Color(hex: "456b47")  // deep forest — hero + primary CTAs
    static let heroLight      = Color(hex: "5d8560")  // hero gradient highlight
    static let urgent         = Color(hex: "a8543a")  // crisis only — deliberately NOT green

    // Sage support family (completion / nature / care team)
    static let sage           = Color(hex: "5f7d52")
    static let sageDeep       = Color(hex: "445c3d")
    static let sageText       = Color(hex: "3a4d34")
    static let sageAvatar     = Color(hex: "ccdabe")

    // Text — ink greens
    static let heading1       = Color(hex: "26402a")
    static let heading2       = Color(hex: "2c4830")
    static let heading3       = Color(hex: "335234")
    static let body           = Color(hex: "53664e")
    static let warmBody       = Color(hex: "6b5f3e")
    static let muted          = Color(hex: "72856b")
    static let muted2         = Color(hex: "82937a")
    static let muted3         = Color(hex: "90a087")

    // On-dark
    static let onPrimary      = Color(hex: "f4f9ef")
    static let onSage         = Color(hex: "f6faf2")

    // Effects & accents
    static let cardShadow     = Color(hex: "3a4d38")            // used with .opacity at call sites
    static let ctaShadowBase  = Color(hex: "39573b")            // primary CTA glow
    static let sageShadow     = Color(hex: "40543a")
    static let chevron        = Color(hex: "a9bda0")
    static let accentTint     = Color(hex: "e2eedd")            // pale-leaf highlight tint
    static let dashedBorder   = Color(hex: "b6c9ab")
    static let safetyIconBG   = Color(hex: "e6e2cd")
    static let alertIcon      = Color(hex: "a8763a")
}

// MARK: - App shell gradient (botanical glass base)

extension Token {
    static let shellGradient = LinearGradient(
        colors: [shellTop, shellMid, shellBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography
//
// Serif display for headings/numbers (dark-green serif), sans for UI.

/// Global type scale set by the accessibility "text size" preference. Read inside
/// the Font helpers; a `settingsVersion` bump rebuilds the tree so it takes effect.
enum AppType {
    static var scale: CGFloat = 1
}

extension Font {
    /// Serif display — real Newsreader when the bundled font registered,
    /// system serif otherwise.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = SolaceFonts.serifName {
            return .custom(name, size: size * AppType.scale).weight(weight)
        }
        return .system(size: size * AppType.scale, weight: weight, design: .serif)
    }

    /// Sans body / UI — real Hanken Grotesque when available, system otherwise.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = SolaceFonts.sansName {
            return .custom(name, size: size * AppType.scale).weight(weight)
        }
        return .system(size: size * AppType.scale, weight: weight, design: .default)
    }
}
