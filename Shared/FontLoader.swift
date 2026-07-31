import UIKit
import CoreText

// MARK: - Bundled brand fonts
//
// The design handoff specifies Newsreader (serif display) and Hanken Grotesque
// (sans UI). The variable TTFs live in Shared/Fonts and are registered at
// runtime with CoreText, which keeps the hand-written project file free of
// Info.plist font arrays. If registration fails for any reason, callers fall
// back to the system serif/sans, so the app never breaks over a font.

public enum SolaceFonts {
    /// Resolved font names, discovered after registration. Nil means fall back.
    public private(set) static var serifName: String? = nil
    public private(set) static var sansName: String? = nil

    public static func register() {
        for file in ["Newsreader", "HankenGrotesque"] {
            if let url = Bundle.main.url(forResource: file, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        serifName = fontName(familyContains: "Newsreader")
        sansName = fontName(familyContains: "Hanken")
    }

    private static func fontName(familyContains needle: String) -> String? {
        guard let family = UIFont.familyNames.first(where: { $0.localizedCaseInsensitiveContains(needle) }),
              let name = UIFont.fontNames(forFamilyName: family).first else { return nil }
        return name
    }
}
