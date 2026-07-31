import SwiftUI

// Botanical palette for the caregiver app — same family as the patient app,
// defined locally because the two targets share only Shared/SharedCare.swift.

extension Color {
    init(careHex hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

enum CareToken {
    static let shellTop    = Color(careHex: "f3f7ee")
    static let shellMid    = Color(careHex: "e7efdf")
    static let shellBottom = Color(careHex: "d9e5cf")
    static let card        = Color.white.opacity(0.74)
    static let border      = Color(careHex: "dce6d1")
    static let primary     = Color(careHex: "456b47")
    static let sage        = Color(careHex: "5f7d52")
    static let sageDeep    = Color(careHex: "445c3d")
    static let sageCard    = Color(careHex: "e4ecdc")
    static let sageAvatar  = Color(careHex: "ccdabe")
    static let accentTint  = Color(careHex: "e2eedd")
    static let heading     = Color(careHex: "2c4830")
    static let body        = Color(careHex: "53664e")
    static let muted       = Color(careHex: "82937a")
    static let muted2      = Color(careHex: "90a087")
    static let onPrimary   = Color(careHex: "f4f9ef")
    static let shadow      = Color(careHex: "3a4d38")
    static let borderChip  = Color(careHex: "d3e0c7")
    static let ink         = Color(careHex: "26402a")

    static let gradient = LinearGradient(
        colors: [shellTop, shellMid, shellBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Font {
    /// Serif accents — real Newsreader when the bundled font registered.
    static func careSerif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        if let name = SolaceFonts.serifName {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
}

/// Minimal copy of the patient app's mood scale, for rendering the week dots.
struct CareMood {
    let word: String
    let color: Color
    let fill: Double

    static let all: [CareMood] = [
        CareMood(word: "Good",     color: Color(careHex: "7a8b6f"), fill: 0.10),
        CareMood(word: "Okay",     color: Color(careHex: "9a9b63"), fill: 0.32),
        CareMood(word: "Low",      color: Color(careHex: "cba24a"), fill: 0.55),
        CareMood(word: "Hard",     color: Color(careHex: "c0764a"), fill: 0.78),
        CareMood(word: "Very low", color: Color(careHex: "a8543a"), fill: 1.00),
    ]

    static func at(_ i: Int) -> CareMood? {
        guard all.indices.contains(i) else { return nil }
        return all[i]
    }
}
