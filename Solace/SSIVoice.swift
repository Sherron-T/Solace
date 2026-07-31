import SwiftUI
import FoundationModels

// MARK: - Voice → answer interpretation for SSI survey screens
//
// Two tiers, cheapest first:
// 1. Keyword overlap against the visible options (offline, instant).
// 2. Apple Intelligence (on-device FoundationModels) when keywords can't
//    decide. Never used for safety decisions, only option matching.
// Voice selects an answer; it never advances the screen. Unmatched speech on
// option screens lands in the "type my own" field, so the person's own words
// are always kept.

enum SSIVoiceInterpreter {
    static func moodIndex(from transcript: String) -> Int? {
        keywordMood(transcript)
    }

    static func energyIndex(from transcript: String) -> Int? {
        keywordEnergy(transcript)
    }

    /// 1…4 on the agree scale, or nil.
    static func agreeIndex(from transcript: String) -> Int? {
        let t = normalized(transcript)
        let strongly = t.contains("strongly") || t.contains("really") || t.contains("very")
        if t.contains("disagree") || t.contains("not true") || t.contains("no ") || t == "no" {
            return strongly ? 1 : 2
        }
        if t.contains("agree") || t.contains("true") || t.contains("yes") || t.contains("yeah") {
            return strongly ? 4 : 3
        }
        return nil
    }

    /// A number in `range`, spoken as digits or words.
    static func number(from transcript: String, in range: ClosedRange<Int>) -> Int? {
        let t = normalized(transcript)
        if let match = t.range(of: #"\b([0-9]|10)\b"#, options: .regularExpression),
           let n = Int(t[match]) {
            return min(max(n, range.lowerBound), range.upperBound)
        }
        let words: [(String, Int)] = [
            ("zero", 0), ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
        ]
        for (word, n) in words where t.contains(word) {
            return min(max(n, range.lowerBound), range.upperBound)
        }
        return nil
    }

    /// Best option by content-word overlap. Nil when nothing overlaps.
    static func keywordMatch(_ transcript: String, options: [String]) -> String? {
        let spoken = contentWords(transcript)
        guard !spoken.isEmpty else { return nil }
        var best: (option: String, hits: Int)? = nil
        for option in options {
            let hits = contentWords(option).intersection(spoken).count
            if hits > (best?.hits ?? 0) { best = (option, hits) }
        }
        return best?.option
    }

    /// Full ladder: keywords, then Apple Intelligence.
    static func pickOption(_ transcript: String, options: [String]) async -> String? {
        if let match = keywordMatch(transcript, options: options) { return match }
        if #available(iOS 26.0, *) {
            return await aiMatch(transcript, options: options)
        }
        return nil
    }

    @available(iOS 26.0, *)
    private static func aiMatch(_ transcript: String, options: [String]) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let numbered = options.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You match what a stroke survivor said out loud to one option from a list.
            Answer with the option number only. Use 0 when nothing fits.
            Never guess about safety or crisis topics; use 0 for those.
            """
        )
        do {
            let response = try await session.respond(
                to: "They said: \"\(transcript)\"\nOptions:\n\(numbered)",
                generating: AIOptionChoice.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.0,
                                           maximumResponseTokens: 40)
            )
            let index = response.content.optionNumber
            guard (1...options.count).contains(index) else { return nil }
            return options[index - 1]
        } catch {
            return nil
        }
    }

    /// Free-form check-in: condense whatever was said ("didn't sleep, arm is
    /// sore, but my daughter visited") onto the 5-point mood scale and the
    /// 3-point energy scale in one pass. Keywords first, Apple Intelligence
    /// when they can't decide. Either value may come back nil.
    static func condenseCheckin(_ transcript: String) async -> (mood: Int?, energy: Int?) {
        var mood = keywordMood(transcript)
        var energy = keywordEnergy(transcript)
        if (mood == nil || energy == nil), #available(iOS 26.0, *) {
            let ai = await aiCheckin(transcript)
            mood = mood ?? ai.mood
            energy = energy ?? ai.energy
        }
        return (mood, energy)
    }

    private static func keywordMood(_ transcript: String) -> Int? {
        let t = normalized(transcript)
        if t.contains("very low") || t.contains("terrible") || t.contains("awful") || t.contains("worst") { return 4 }
        if t.contains("hard") || t.contains("bad") || t.contains("rough") || t.contains("struggl") { return 3 }
        if t.contains("low") || t.contains("down") || t.contains("sad") { return 2 }
        if t.contains("okay") || t.contains("ok") || t.contains("alright") || t.contains("fine") { return 1 }
        if t.contains("good") || t.contains("great") || t.contains("happy") { return 0 }
        return nil
    }

    private static func keywordEnergy(_ transcript: String) -> Int? {
        let t = normalized(transcript)
        if t.contains("exhausted") || t.contains("tired") || t.contains("no energy")
            || t.contains("worn out") || t.contains("sleepy") || t.contains("didn t sleep") { return 0 }
        if t.contains("energetic") || t.contains("lots of energy") || t.contains("full of energy") { return 2 }
        if t.contains("steady") || t.contains("some energy") { return 1 }
        return nil
    }

    @available(iOS 26.0, *)
    private static func aiCheckin(_ transcript: String) async -> (mood: Int?, energy: Int?) {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return (nil, nil) }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You listen to a stroke survivor describing their day and map it onto
            two scales. Mood: 1 good, 2 okay, 3 low, 4 hard, 5 very low.
            Energy: 1 tired, 2 steady, 3 energetic.
            Use 0 for either when you truly cannot tell. Never guess about
            crisis or safety topics; that is not your job here.
            """
        )
        do {
            let response = try await session.respond(
                to: "They said: \"\(transcript)\"",
                generating: AICheckinReading.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.0,
                                           maximumResponseTokens: 60)
            )
            let content = response.content
            let mood = (1...5).contains(content.moodNumber) ? content.moodNumber - 1 : nil
            let energy = (1...3).contains(content.energyNumber) ? content.energyNumber - 1 : nil
            return (mood, energy)
        } catch {
            return (nil, nil)
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "i", "im", "me", "my", "myself", "to", "of", "or", "and",
        "with", "do", "one", "feel", "feeling", "more", "like", "would", "be",
        "it", "is", "that", "this", "am", "was", "get", "getting",
    ]

    private static func contentWords(_ text: String) -> Set<String> {
        Set(normalized(text).split(separator: " ").map(String.init))
            .subtracting(stopWords)
    }
}

@available(iOS 26.0, *)
@Generable(description: "The number of the option that best matches, or 0 if none fit.")
private struct AIOptionChoice {
    var optionNumber: Int
}

@available(iOS 26.0, *)
@Generable(description: "Mood 1-5 (good to very low) and energy 1-3 (tired to energetic) heard in what the person said; 0 when unclear.")
private struct AICheckinReading {
    var moodNumber: Int
    var energyNumber: Int
}
