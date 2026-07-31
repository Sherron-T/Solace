import Foundation
import FoundationModels

/// Turns the week's structured data (check-ins, mood curve, completions, the
/// behavioral-activation lift tally) into two pieces of plain language:
/// a short dashboard synthesis for the care team, and a warm message ready to
/// share with family. Runs on-device via Apple Intelligence; a deterministic
/// composer takes over when the model is unavailable, so the feature always
/// works. Input is structured app data only — never clinical notes — so there
/// is nothing medical for the model to invent.
enum CareSummaryAI {
    struct Summary {
        let dashboard: String
        let familyMessage: String
        let source: String   // "Apple Intelligence" | "Local"
    }

    static func summarize(snapshot: CareSnapshot, feed: [CareUpdate]) async -> Summary {
        if #available(iOS 26.0, *),
           let ai = await aiSummary(snapshot: snapshot, feed: feed) {
            return ai
        }
        return localSummary(snapshot: snapshot)
    }

    // MARK: Apple Intelligence path

    @available(iOS 26.0, *)
    private static func aiSummary(snapshot: CareSnapshot, feed: [CareUpdate]) async -> Summary? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You summarize a stroke survivor's week for their care team and family,
            using only the structured facts given. Warm, plain, adult language.
            Never diagnose, never give medical advice, never mention medication.
            Never invent events that are not in the facts. If the week was hard,
            say so gently and point at what helped. No exclamation marks.
            Write flowing full sentences, never staccato fragments, and never
            use em-dashes.
            """
        )

        let moodWords = ["good", "okay", "low", "hard", "very low"]
        let week = snapshot.week
            .map { $0 >= 0 && $0 < moodWords.count ? moodWords[$0] : "not logged" }
            .joined(separator: ", ")
        let recent = feed.prefix(6).map { "- \($0.text)" }.joined(separator: "\n")

        let prompt = """
        Facts about \(snapshot.patientName)'s week:
        - Mood by day, oldest to today: \(week)
        - Current check-in streak: \(snapshot.streak) days
        - Activities completed this week: \(snapshot.wins) of a \(snapshot.weeklyGoal) goal
        - After doing an activity, mood lifted \(snapshot.liftedCount) of \(snapshot.afterCount) times
        Recent updates:
        \(recent)

        Write:
        - dashboard: 2 short sentences for the care team about the pattern and what helped
        - familyMessage: 2-3 warm sentences to send the family, starting with an update on \(snapshot.patientName)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: AIWeekSummary.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.2,
                                           maximumResponseTokens: 400)
            )
            let content = response.content
            guard !content.dashboard.isEmpty, !content.familyMessage.isEmpty else { return nil }
            return Summary(dashboard: content.dashboard,
                           familyMessage: content.familyMessage,
                           source: "Apple Intelligence")
        } catch {
            return nil
        }
    }

    // MARK: Deterministic fallback

    static func localSummary(snapshot: CareSnapshot) -> Summary {
        let logged = snapshot.week.filter { $0 >= 0 }
        let heavy = logged.filter { $0 >= 3 }.count
        let liftLine: String
        if snapshot.afterCount > 0 {
            liftLine = "Doing small activities lifted mood \(snapshot.liftedCount) of \(snapshot.afterCount) times."
        } else {
            liftLine = "No after-activity check-ins yet this week."
        }
        let weekLine = heavy >= 3
            ? "This week ran heavy on \(heavy) of \(logged.count) logged days."
            : "Mood held fairly steady across \(logged.count) logged days."
        let dashboard = "\(weekLine) \(liftLine)"
        let family = "Update on \(snapshot.patientName): they checked in \(logged.count) days this week and completed \(snapshot.wins) activities. \(liftLine)"
        return Summary(dashboard: dashboard, familyMessage: family, source: "Local")
    }
}

@available(iOS 26.0, *)
@Generable(description: "A plain-language weekly summary derived only from the given facts.")
private struct AIWeekSummary {
    var dashboard: String
    var familyMessage: String
}
