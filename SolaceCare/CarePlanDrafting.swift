import Foundation
import FoundationModels

/// Replaceable drafting seam for the caregiver app.
///
/// The preferred path uses Apple's on-device Foundation Models framework
/// (Apple Intelligence). If it is unavailable on this device/simulator, the
/// conservative local draft keeps the prototype usable offline. The caregiver
/// review/approve step remains in front of the patient either way.
enum CarePlanDrafting {
    struct Result {
        let activities: [CarePlanActivity]
        let source: String
        let detail: String
    }

    static func draft(from note: String) async -> Result {
        if #available(iOS 26.0, *),
           let appleDraft = await draftWithAppleIntelligence(from: note),
           !appleDraft.isEmpty {
            return Result(
                // Appearance is never trusted from the model — CarePlanStyle
                // derives valid symbols and on-palette colors from the words.
                activities: appleDraft.map(CarePlanStyle.restyled),
                source: "Apple Intelligence",
                detail: "Drafted on device, review before approving."
            )
        }

        return Result(
            activities: localDraft(from: note).map(CarePlanStyle.restyled),
            source: "Local fallback",
            detail: "Apple Intelligence was unavailable, so Solace used the offline rule-based draft."
        )
    }

    static func localDraft(from note: String) -> [CarePlanActivity] {
        let chunks = instructionChunks(from: note)
        let drafts = chunks.prefix(5).map(makeActivity)
        if !drafts.isEmpty { return drafts }

        let trimmed = clean(note)
        guard !trimmed.isEmpty else { return [] }
        return [makeActivity(from: trimmed)]
    }

    @available(iOS 26.0, *)
    private static func draftWithAppleIntelligence(from note: String) async -> [CarePlanActivity]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You draft small behavioral-activation steps for a post-stroke depression app.
            The user is a care-team member or researcher, not the patient.
            Use only the pasted note. Do not invent new medical advice.
            Keep language adult, calm, plain, and brief.
            Write flowing full sentences, never staccato fragments, and never
            use em-dashes.
            Each activity must be one small tap-friendly action.
            If a step is physical therapy, include a stop-if-unsafe or stop-if-it-hurts caution.
            Do not include diagnosis, medication changes, crisis counseling, or anything beyond the note.
            """
        )

        let prompt = """
        Convert this care-team note into 1 to 5 patient-facing daily activities.
        Use short labels, one-line subtitles, and one simple instruction per activity.

        Return:
        - label: 2 to 4 words
        - sub: one short sentence
        - title: same idea as label
        - instruction: one or two short patient-facing sentences
        - symbol: one SF Symbol name
        - colorHex and tintHex: calm accessible hex colors
        - isPT: true only for physical therapy or movement practice
        - valueTags: any of people, independent, strength, joy
        - effort: 0 restful, 1 moderate, 2 active

        Note:
        \(note)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: AICarePlanDraftResponse.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.1,
                    maximumResponseTokens: 1200
                )
            )
            let source = clean(note)
            return response.content.activities
                .prefix(5)
                .map { $0.activity(sourceNote: source) }
                .filter { !$0.label.isEmpty && !$0.instruction.isEmpty }
        } catch {
            return nil
        }
    }

    private static func instructionChunks(from note: String) -> [String] {
        let normalized = note
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "•", with: "\n")
            .replacingOccurrences(of: " - ", with: "\n")

        let lineChunks = normalized
            .split(whereSeparator: \.isNewline)
            .map { clean(String($0)) }
            .filter { $0.count >= 8 }

        if lineChunks.count >= 2 { return Array(lineChunks.prefix(8)) }

        return normalized
            .split(whereSeparator: { ".!?;".contains($0) })
            .map { clean(String($0)) }
            .filter { $0.count >= 8 }
            .prefix(8)
            .map { $0 }
    }

    private static func makeActivity(from chunk: String) -> CarePlanActivity {
        let lower = chunk.lowercased()
        let snippet = patientSnippet(chunk)

        if containsAny(lower, ["call", "family", "friend", "text", "message", "social"]) {
            return CarePlanActivity(
                label: "Reach out once",
                sub: "One short check-in.",
                title: "Reach out once",
                instruction: "Send one text or make one short call, and you can stop after a minute.",
                symbol: "phone.fill",
                colorHex: "4a7d78",
                tintHex: "dfecea",
                isPT: false,
                valueTags: ["people"],
                effort: 1,
                sourceNote: chunk
            )
        }

        if containsAny(lower, ["walk", "walking", "steps", "stand", "standing", "balance", "sit to stand"]) {
            return CarePlanActivity(
                label: "Practice safe movement",
                sub: "One short round from the plan.",
                title: "Practice safe movement",
                instruction: "Follow this care-team step: \(snippet). Stop if you feel unsafe.",
                symbol: "figure.walk",
                colorHex: "3f6142",
                tintHex: "dfe9de",
                isPT: true,
                valueTags: ["strength", "independent"],
                effort: 2,
                sourceNote: chunk
            )
        }

        if containsAny(lower, ["exercise", "therapy", "physio", "physical therapy", "stretch", "range of motion", "shoulder", "arm", "hand", "leg"]) {
            return CarePlanActivity(
                label: "Do one therapy set",
                sub: "Use the care-team instructions.",
                title: "Do one therapy set",
                instruction: "Follow this care-team step: \(snippet). Stop if it hurts.",
                symbol: "figure.strengthtraining.traditional",
                colorHex: "3f6142",
                tintHex: "dfe9de",
                isPT: true,
                valueTags: ["strength", "independent"],
                effort: 2,
                sourceNote: chunk
            )
        }

        if containsAny(lower, ["speech", "aphasia", "word", "words", "read", "name"]) {
            return CarePlanActivity(
                label: "Practice one word",
                sub: "One quiet speech step.",
                title: "Practice one word",
                instruction: "Try this care-team step once: \(snippet). One try counts.",
                symbol: "text.bubble.fill",
                colorHex: "5a7590",
                tintHex: "e3eaf0",
                isPT: false,
                valueTags: ["independent"],
                effort: 1,
                sourceNote: chunk
            )
        }

        if containsAny(lower, ["outside", "sun", "window", "fresh air"]) {
            return CarePlanActivity(
                label: "Sit near fresh air",
                sub: "Five quiet minutes.",
                title: "Sit near fresh air",
                instruction: "Sit by a window or outside for five minutes, and that is enough.",
                symbol: "sun.max",
                colorHex: "5f8a55",
                tintHex: "e4efdc",
                isPT: false,
                valueTags: ["joy", "independent"],
                effort: 1,
                sourceNote: chunk
            )
        }

        return CarePlanActivity(
            label: shortLabel(from: chunk),
            sub: "One small care-plan step.",
            title: shortTitle(from: chunk),
            instruction: "Try this care-team step: \(snippet). One attempt counts.",
            symbol: "checkmark.circle.fill",
            colorHex: "5f7d52",
            tintHex: "e4ecdc",
            isPT: false,
            valueTags: [],
            effort: 1,
            sourceNote: chunk
        )
    }

    private static func clean(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func patientSnippet(_ text: String) -> String {
        let cleaned = clean(text)
        if cleaned.count <= 92 { return cleaned }
        let prefix = cleaned.prefix(89)
        let safeBreak = prefix.lastIndex(of: " ") ?? prefix.endIndex
        return String(prefix[..<safeBreak]) + "..."
    }

    private static func shortLabel(from text: String) -> String {
        let words = clean(text).split(separator: " ").prefix(4)
        let label = words.joined(separator: " ")
        return label.isEmpty ? "Care-plan step" : label
    }

    private static func shortTitle(from text: String) -> String {
        let label = shortLabel(from: text)
        return label == "Care-plan step" ? label : label.prefix(1).uppercased() + label.dropFirst()
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

@available(iOS 26.0, *)
@Generable(description: "A group of patient-facing activities drafted from a care-team note.")
private struct AICarePlanDraftResponse {
    var activities: [AICarePlanActivityDraft]
}

@available(iOS 26.0, *)
@Generable(description: "One small, clinician-reviewed activity candidate for a stroke survivor.")
private struct AICarePlanActivityDraft {
    var label: String
    var sub: String
    var title: String
    var instruction: String
    var symbol: String
    var colorHex: String
    var tintHex: String
    var isPT: Bool
    var valueTags: [String]
    var effort: Int

    func activity(sourceNote: String) -> CarePlanActivity {
        let normalizedTags = valueTags
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ["people", "independent", "strength", "joy"].contains($0) }

        return CarePlanActivity(
            label: sanitized(label, maxLength: 34),
            sub: sanitized(sub, maxLength: 58),
            title: sanitized(title.isEmpty ? label : title, maxLength: 44),
            instruction: sanitized(instruction, maxLength: 150),
            symbol: safeSymbol(symbol, isPT: isPT),
            colorHex: safeHex(colorHex, fallback: isPT ? "3f6142" : "5f7d52"),
            tintHex: safeHex(tintHex, fallback: isPT ? "dfe9de" : "e4ecdc"),
            isPT: isPT,
            valueTags: Array(Set(normalizedTags)).sorted(),
            effort: max(0, min(2, effort)),
            sourceNote: sourceNote
        )
    }

    private func sanitized(_ text: String, maxLength: Int) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard trimmed.count > maxLength else { return trimmed }
        let prefix = trimmed.prefix(maxLength - 3)
        let safeBreak = prefix.lastIndex(of: " ") ?? prefix.endIndex
        return String(prefix[..<safeBreak]) + "..."
    }

    private func safeHex(_ value: String, fallback: String) -> String {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard hex.range(of: #"^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else {
            return fallback
        }
        return hex
    }

    private func safeSymbol(_ value: String, isPT: Bool) -> String {
        let allowed = [
            "phone.fill", "person.2.fill", "figure.walk",
            "figure.strengthtraining.traditional", "text.bubble.fill",
            "sun.max", "music.note", "photo", "checkmark.circle.fill"
        ]
        return allowed.contains(value) ? value : (isPT ? "figure.walk" : "checkmark.circle.fill")
    }
}
