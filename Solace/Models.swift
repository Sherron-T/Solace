import SwiftUI

// MARK: - Screen state machine

enum Screen: Equatable {
    case home, mood, energy, confirm, activities, doing, rehabGame, after, done, trend, safety, boost
}

// MARK: - Visuospatial neglect (which side of the world gets missed)

enum NeglectSide: String {
    case none, left, right
}

// MARK: - Energy (second axis of the zero-type check-in matrix)

struct Energy: Identifiable {
    let index: Int
    let word: String
    let symbol: String
    /// Short phrase for synthesized caregiver updates: "energy is low".
    let phrase: String

    var id: Int { index }

    static let all: [Energy] = [
        Energy(index: 0, word: "Tired",     symbol: "battery.25percent",  phrase: "energy is low"),
        Energy(index: 1, word: "Steady",    symbol: "battery.50percent",  phrase: "energy is steady"),
        Energy(index: 2, word: "Energetic", symbol: "battery.100percent", phrase: "energy is good"),
    ]

    static func at(_ index: Int?) -> Energy? {
        guard let i = index, all.indices.contains(i) else { return nil }
        return all[i]
    }
}

// MARK: - Mood (DISCs-style scale)

struct Mood: Identifiable {
    let index: Int
    let word: String
    let color: Color
    /// 0…1 — how full the DISCs circle is. Severity rises with fill.
    let fill: Double

    var id: Int { index }

    /// 0 = open smile … 4 = clear frown. Drives the confirm-screen face.
    var mouth: MoodMouth { MoodMouth(rawValue: index) ?? .flat }

    static let all: [Mood] = [
        Mood(index: 0, word: "Good",     color: Color(hex: "7a8b6f"), fill: 0.10),
        Mood(index: 1, word: "Okay",     color: Color(hex: "9a9b63"), fill: 0.32),
        Mood(index: 2, word: "Low",      color: Color(hex: "cba24a"), fill: 0.55),
        Mood(index: 3, word: "Hard",     color: Color(hex: "c0764a"), fill: 0.78),
        Mood(index: 4, word: "Very low", color: Color(hex: "a8543a"), fill: 1.00),
    ]

    static func at(_ index: Int?) -> Mood? {
        guard let i = index, all.indices.contains(i) else { return nil }
        return all[i]
    }

    /// Supportive copy shown on the confirm screen (index 4 routes to safety, no copy).
    var confirmMessage: String {
        switch index {
        case 0: return "Glad to hear it, let’s keep the good going with one small thing."
        case 1: return "Okay is okay, and a small step can help it hold."
        case 2: return "Thanks for being honest, let’s try one gentle thing together."
        case 3: return "Hard days are real, so we’ll keep it to just one small thing."
        default: return ""
        }
    }
}

/// The five mouth shapes, smile → flat → frown.
enum MoodMouth: Int {
    case smile = 0, softSmile, flat, slightFrown, frown
}

// MARK: - Personal values (single-session intervention anchor)

struct PersonalValue: Identifiable {
    let id: String
    let label: String
    let symbol: String
    /// Short phrase used inside sentences: "one small thing for …"
    let phrase: String

    static let all: [PersonalValue] = [
        PersonalValue(id: "people",      label: "Family & friends",       symbol: "person.2.fill",  phrase: "the people you love"),
        PersonalValue(id: "independent", label: "Feeling independent",    symbol: "figure.walk",    phrase: "your independence"),
        PersonalValue(id: "strength",    label: "Getting stronger",       symbol: "dumbbell.fill",  phrase: "your strength"),
        PersonalValue(id: "joy",         label: "Enjoying little things", symbol: "sparkles",       phrase: "the little things you enjoy"),
    ]

    static func with(id: String?) -> PersonalValue? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

// MARK: - Post-activity re-check (behavioral activation feedback loop)

enum AfterFeeling: String {
    case better, same, hard
}

// MARK: - Activity (behavioral activation)

struct Activity: Identifiable {
    let id: String
    let label: String
    let sub: String
    let title: String
    let instruction: String
    let color: Color
    let tint: Color
    let isPT: Bool
    /// SF Symbol standing in for the Lucide glyph.
    let symbol: String
    /// Personal values this activity serves — used to surface "for you" matches.
    let valueTags: [String]
    /// 0 = restful, 1 = moderate, 2 = active — matched against today's energy.
    let effort: Int
    /// True only for the built-in tap-along rehab game.
    let usesRehabGame: Bool
    /// True when the activity was approved by the care team in SolaceCare.
    let isCarePlan: Bool
    /// Original care-team note chunk, kept out of the patient UI unless needed.
    let sourceSnippet: String?

    static let all: [Activity] = [
        Activity(id: "call",
                 label: "Call someone",
                 sub: "One person, a few minutes.",
                 title: "Call someone",
                 instruction: "Pick one person, tap call, and keep it as short as you like.",
                 color: Color(hex: "4a7d78"), tint: Color(hex: "dfecea"),
                 isPT: false, symbol: "phone.fill",
                 valueTags: ["people"], effort: 1,
                 usesRehabGame: false, isCarePlan: false, sourceSnippet: nil),
        Activity(id: "outside",
                 label: "Sit outside",
                 sub: "Five minutes of fresh air.",
                 title: "Sit outside",
                 instruction: "Find a chair near a window or door, and five minutes there is plenty.",
                 color: Color(hex: "5f8a55"), tint: Color(hex: "e4efdc"),
                 isPT: false, symbol: "sun.max",
                 valueTags: ["joy", "independent"], effort: 1,
                 usesRehabGame: false, isCarePlan: false, sourceSnippet: nil),
        Activity(id: "pt",
                 label: "Today’s exercises",
                 sub: "Gentle taps, counted with you.",
                 title: "Today’s exercises",
                 instruction: "Tap each leaf as it appears, nice and easy, and five taps is the whole set.",
                 color: Color(hex: "3f6142"), tint: Color(hex: "dfe9de"),
                 isPT: true, symbol: "figure.strengthtraining.traditional",
                 valueTags: ["strength", "independent"], effort: 2,
                 usesRehabGame: true, isCarePlan: false, sourceSnippet: nil),
        Activity(id: "music",
                 label: "Listen to music",
                 sub: "One song you love.",
                 title: "Listen to music",
                 instruction: "Put on one song that means something to you and just listen.",
                 color: Color(hex: "5a7590"), tint: Color(hex: "e3eaf0"),
                 isPT: false, symbol: "music.note",
                 valueTags: ["joy"], effort: 0,
                 usesRehabGame: false, isCarePlan: false, sourceSnippet: nil),
        Activity(id: "photo",
                 label: "Look at a photo",
                 sub: "Someone or somewhere good.",
                 title: "Look at a photo",
                 instruction: "Open one photo that makes you smile and sit with it for a moment.",
                 color: Color(hex: "8a6b7d"), tint: Color(hex: "eee6eb"),
                 isPT: false, symbol: "photo",
                 valueTags: ["people", "joy"], effort: 0,
                 usesRehabGame: false, isCarePlan: false, sourceSnippet: nil),
    ]

    static func with(id: String?) -> Activity? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

extension Activity {
    /// An activity the patient chose for themselves in the single-session plan.
    /// Appearance comes from the same deterministic styling as care-plan items.
    static func ssiAction(_ text: String, index: Int, valueID: String?) -> Activity {
        let s = CarePlanStyle.style(for: text)
        return Activity(id: "ssi.\(index)",
                 label: text,
                 sub: "From your own plan",
                 title: text,
                 instruction: "The smallest safe version counts, and doing part of it is still doing it.",
                 color: Color(hex: s.colorHex),
                 tint: Color(hex: s.tintHex),
                 isPT: false,
                 symbol: s.symbol,
                 valueTags: valueID.map { [$0] } ?? [],
                 effort: 1,
                 usesRehabGame: false,
                 isCarePlan: false,
                 sourceSnippet: nil)
    }

    static func carePlan(_ item: CarePlanActivity) -> Activity {
        // Normalize appearance even for items stored before the style rules
        // existed — old drafts with hallucinated symbols/colors self-heal.
        let activity = CarePlanStyle.restyled(item)
        return Activity(id: "careplan.\(activity.id)",
                 label: activity.label,
                 sub: activity.sub,
                 title: activity.title,
                 instruction: activity.instruction,
                 color: Color(hex: activity.colorHex),
                 tint: Color(hex: activity.tintHex),
                 isPT: activity.isPT,
                 symbol: activity.symbol,
                 valueTags: activity.valueTags,
                 effort: max(0, min(2, activity.effort)),
                 usesRehabGame: false,
                 isCarePlan: true,
                 sourceSnippet: activity.sourceNote)
    }
}
