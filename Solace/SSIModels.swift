import Foundation

// MARK: - Science-informed single-session intervention (SSI)
//
// Structure adapted from the Koko / Lab for Scalable Mental Health
// single-session consultation flow, reworded for adult stroke recovery.
// Components: solution-focused preferred future + scaling question,
// behavioral activation action choice, implementation intentions
// ("if obstacle, then response"), and pre/post hopelessness + readiness.
//
// Evidence base (kept here on purpose, for the demo pitch):
// - Koko/LSMH single-session consultation: https://ssi.kokocares.org/lsmh/ssc-en
// - Schleider et al. 2022, RCT of online SSIs for adolescent depression:
//   https://doi.org/10.1038/s41562-021-01235-0
// - Schleider et al. 2020, Project YES open-access SSI evaluation:
//   https://doi.org/10.2196/20513
// - Schleider & Weisz 2017, meta-analysis of single-session interventions:
//   https://doi.org/10.1016/j.jaac.2016.11.007
//
// Supportive, non-diagnostic: this module never claims to treat or replace
// clinical care, and support options stay one tap away on every screen.

// MARK: Stages

enum SSIStage: Int, CaseIterable, Equatable {
    case landing, consent
    case preHope1, preHope2, preHope3, preHope4
    case safetyOffer                // shown only when the pre-check runs high
    case preReadiness
    case psychoedCommon, psychoedStuck, psychoedNoFault, psychoedSmallSteps
    case breathing
    case topStruggle, topHope, selfTalk
    case betterDayPrompt, betterDayFeelings, betterDayActions
    case midpoint, betterDayScale
    case actionIntro, actionOne, actionTwo
    case supportPerson, innerObstacle, obstacleResponse
    case ifThenSummary, almostDone, actionPlan
    case postHope1, postHope2, postHope3, postHope4, postReadiness
    case completion

    /// 0…1 for the progress bar. The optional safety stage doesn't add length.
    var progress: Double {
        let total = Double(SSIStage.completion.rawValue)
        return min(1, Double(rawValue) / total)
    }
}

/// Pure navigation history for the SSI flow. Keeping this independent of the
/// view makes forward/back behavior deterministic and testable.
struct SSIStageHistory {
    private(set) var stage: SSIStage = .landing
    private(set) var trail: [SSIStage] = []

    @discardableResult
    mutating func advance(highHopelessness: Bool) -> SSIStage {
        var next = SSIStage(rawValue: stage.rawValue + 1) ?? .completion
        if next == .safetyOffer && !highHopelessness {
            next = .preReadiness
        }
        trail.append(stage)
        stage = next
        return stage
    }

    @discardableResult
    mutating func goBack() -> SSIStage? {
        guard let previous = trail.popLast() else { return nil }
        stage = previous
        return stage
    }

    mutating func jump(to target: SSIStage) {
        trail.append(stage)
        stage = target
    }
}

// MARK: Response record

struct SSIResponse: Codable {
    var startedAt: Date = Date()
    var completedAt: Date? = nil
    var consentAcceptedAt: Date? = nil

    /// Four items, each 1…4 (strongly disagree … strongly agree).
    var preHopelessness: [Int?] = [nil, nil, nil, nil]
    var preReadiness: Int? = nil

    var topStruggle: String? = nil
    var topHope: String? = nil
    var selfTalkChanges: [String] = []

    var betterDayFeelings: [String] = []
    var betterDayActions: [String] = []
    var betterDayCloseness: Int? = nil

    var selfCareAction1: String? = nil
    var selfCareAction2: String? = nil

    var supportPerson: String? = nil
    var innerObstacle: String? = nil
    var obstacleResponse: String? = nil

    var completedBreathing: Bool = false
    var sharedWithCareTeam: Bool = false

    var postHopelessness: [Int?] = [nil, nil, nil, nil]
    var postReadiness: Int? = nil

    var preHopelessnessSum: Int { preHopelessness.compactMap { $0 }.count == 4 ? preHopelessness.compactMap { $0 }.reduce(0, +) : -1 }
    var postHopelessnessSum: Int { postHopelessness.compactMap { $0 }.count == 4 ? postHopelessness.compactMap { $0 }.reduce(0, +) : -1 }

    /// Gentle safety trigger: agreement ("somewhat/strongly agree") on 3+ of
    /// the 4 pre-check items. Rule-based on purpose — never an LLM decision.
    var highHopelessness: Bool {
        preHopelessness.compactMap { $0 }.filter { $0 >= 3 }.count >= 3
    }

    /// Readiness improvement, only ever reported when positive (no-failure tone).
    var readinessLift: Int? {
        guard let pre = preReadiness, let post = postReadiness, post > pre else { return nil }
        return post - pre
    }
}

// MARK: Option sets (Solace-adapted wording)

enum SSIOptions {
    static let hopelessnessScale = [
        "Strongly disagree", "Somewhat disagree", "Somewhat agree", "Strongly agree",
    ]

    static let hopelessnessItems = [
        "It feels like things cannot get better.",
        "My future feels dark right now.",
        "It feels like things will not work out the way I hope.",
        "It feels hard to try because I may not get what I want.",
    ]

    static let topStruggle = [
        "Feeling disconnected from people",
        "Feeling tired or low-energy",
        "Feeling like I lost independence",
        "Being hard on myself",
        "Feeling stuck",
        "Avoiding rehab or daily tasks",
        "Getting frustrated or angry easily",
        "Worrying about the future",
        "Worrying what others think",
    ]

    static let topHope = [
        "Feel more like myself",
        "Take one rehab or movement step",
        "Reach out to someone",
        "Rebuild part of my daily routine",
        "Be kinder to myself today",
        "Do one positive thing I have been avoiding",
        "Practice staying in the present",
        "Reconnect with what matters to me",
    ]

    static let selfTalk = [
        "Be gentler with myself",
        "Remind myself I can take one step",
        "Remind myself I am doing my best",
        "Notice what I am doing well",
        "Accept what I cannot control today",
        "Forgive myself for mistakes",
        "Remind myself I am stronger than this moment feels",
        "Use a coping skill before giving up",
        "Remember that I am loved or valued",
        "Accept myself as I am today",
    ]

    static let betterDayFeelings = [
        "Feel calmer",
        "Feel more capable",
        "Feel more connected",
        "Feel more motivated",
        "Enjoy something I value",
        "Handle frustration better",
        "Feel more content",
        "Feel more joy",
        "Notice gratitude",
        "Feel more patient with recovery",
    ]

    static let betterDayActions = [
        "Spend time with family",
        "Talk with a friend",
        "Do a rehab exercise",
        "Do a hobby",
        "Get outside or move around safely",
        "Finish a small task",
        "Take care of hygiene or meals",
        "Practice mindfulness",
        "Try something new",
        "Meet or message someone",
    ]

    static let selfCareActions = [
        "Talk with a friend",
        "Do a safe movement or rehab exercise",
        "Sit outside or near a window",
        "Practice slow breathing",
        "Spend time with a pet",
        "Watch something funny or comforting",
        "Check in with a family text thread",
        "Say one kind sentence to myself",
        "Do a short meditation",
        "Make art or music",
        "Prepare a simple meal or drink",
        "Play a game or puzzle",
        "Write or record a short journal note",
        "Ask a trusted person for advice",
        "Pray or do a spiritual practice",
        "Do something kind for someone",
        "Talk with my caregiver or clinician",
    ]

    static let innerObstacle = [
        "Feeling unmotivated",
        "Feeling tired",
        "Pain or body discomfort",
        "Feeling overwhelmed",
        "Feeling very emotional",
        "Fear of failing",
        "Worrying about how things will go",
        "Feeling unsure what to choose",
        "Feeling embarrassed",
        "Feeling like I do not deserve care",
    ]

    static let obstacleResponse = [
        "Break it into a smaller step",
        "Rest first, then try a smaller version",
        "Ask someone for help",
        "Do breathing or another calming exercise",
        "Celebrate doing even part of it",
        "Remind myself that small actions matter",
        "Remind myself I am worthy of care",
        "Ask my care team if this action is safe",
    ]
}

// MARK: Hope → personal value (keeps the rest of the app personalized)

extension SSIResponse {
    /// Map the chosen hope onto the app's PersonalValue ids so activity
    /// ordering and FOR YOU tags keep working after the SSI.
    var impliedValueID: String {
        switch topHope {
        case "Reach out to someone", "Reconnect with what matters to me":
            return "people"
        case "Take one rehab or movement step":
            return "strength"
        case "Rebuild part of my daily routine", "Feel more like myself",
             "Do one positive thing I have been avoiding":
            return "independent"
        case "Be kinder to myself today", "Practice staying in the present":
            return "joy"
        default:
            return "people"
        }
    }
}
