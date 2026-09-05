import Foundation
import UIKit

// MARK: - Care-plan visual style (deterministic, never AI-chosen)
//
// Language models hallucinate SF Symbol names and pick clashing colors, which
// made AI-drafted tasks look broken next to the built-ins. Appearance is now
// derived here, deterministically, from what the step *says* — both apps run
// drafts and stored items through this, so the styling can never regress.

public enum CarePlanStyle {
    /// Curated botanical accents (color, tint). No reds — warm red is reserved
    /// for crisis UI in the patient app.
    private static let palettes: [(color: String, tint: String)] = [
        ("3f6142", "dfe9de"),   // forest — strength / therapy
        ("5f8a55", "e4efdc"),   // moss — movement / outdoors
        ("4a7d78", "dfecea"),   // teal — hands / social
        ("5a7590", "e3eaf0"),   // slate — restful / quiet
    ]

    private static let rules: [(keywords: [String], symbol: String, palette: Int)] = [
        (["walk", "step", "mailbox", "stand", "balance", "stairs"],            "figure.walk",                          1),
        (["arm", "shoulder", "leg", "raise", "lift", "rep", "exercise",
          "therapy", "physio", "strength", "stretch", "range of motion"],      "figure.strengthtraining.traditional",  0),
        (["squeeze", "ball", "grip", "hand", "finger"],                        "hand.raised.fill",                     2),
        (["breath", "breathe", "relax", "calm"],                               "wind",                                 3),
        (["call", "phone", "text", "family", "friend", "social"],              "phone.fill",                           2),
        (["read", "book", "chapter"],                                          "book.fill",                            3),
        (["water", "drink", "hydrate"],                                        "drop.fill",                            2),
        (["rest", "sleep", "nap", "eyes"],                                     "moon.fill",                            3),
        (["music", "song", "listen"],                                          "music.note",                           3),
        (["outside", "sun", "fresh air", "porch", "garden"],                   "sun.max",                              1),
    ]

    /// Symbol + colors for a step, chosen from its own words. Always valid.
    public static func style(for text: String) -> (symbol: String, colorHex: String, tintHex: String) {
        let lower = text.lowercased()
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            let p = palettes[rule.palette]
            return (validated(rule.symbol), p.color, p.tint)
        }
        let p = palettes[0]
        return (validated("checklist"), p.color, p.tint)
    }

    /// Returns the symbol if the OS actually has it, else a safe fallback.
    public static func validated(_ symbol: String) -> String {
        UIImage(systemName: symbol) != nil ? symbol : "checkmark.circle.fill"
    }

    /// A copy of the activity with normalized appearance.
    public static func restyled(_ a: CarePlanActivity) -> CarePlanActivity {
        let s = style(for: a.label + " " + a.sub + " " + a.instruction)
        return CarePlanActivity(id: a.id, label: a.label, sub: a.sub, title: a.title,
                                instruction: a.instruction,
                                symbol: s.symbol, colorHex: s.colorHex, tintHex: s.tintHex,
                                isPT: a.isPT, valueTags: a.valueTags, effort: a.effort,
                                sourceNote: a.sourceNote, createdAt: a.createdAt)
    }
}

// MARK: - Shared care data (compiled into BOTH apps)
//
// The patient app (Solace) writes; the caregiver app (SolaceCare) reads.
// Storage is an App Group container — a real cross-app data layer that works
// offline and on the simulator with no accounts. This file is the backend seam:
// to move to Firebase/CloudKit, reimplement SharedCareStore's four functions
// against the remote SDK and nothing else changes.

public enum SharedCare {
    public static let suiteName = "group.com.solace.shared"
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

/// One synthesized feed entry ("Sherron completed 'Sit outside'…").
public struct CareUpdate: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let text: String
    /// "checkin" | "activity" | "rehab" — drives the feed icon.
    public let kind: String

    public init(text: String, kind: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.kind = kind
    }
}

/// A short, caregiver-authored message that travels back to the survivor.
/// Messages are deliberately plain text and small so they remain useful when
/// the shared care payload is cached offline.
public struct CaregiverMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let text: String
    /// "encouragement" | "checkin" | "plan" — drives the patient-side icon.
    public let kind: String

    public init(text: String, kind: String = "encouragement", date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.kind = kind
    }
}

/// Rolled-up patient status for the caregiver dashboard.
public struct CareSnapshot: Codable {
    public var patientName: String
    public var streak: Int
    public var wins: Int
    public var weeklyGoal: Int
    /// Last 7 days of mood indices; -1 = not logged.
    public var week: [Int]
    public var liftedCount: Int
    public var afterCount: Int
    public var updatedAt: Date

    public init(patientName: String, streak: Int, wins: Int, weeklyGoal: Int,
                week: [Int], liftedCount: Int, afterCount: Int, updatedAt: Date = Date()) {
        self.patientName = patientName
        self.streak = streak
        self.wins = wins
        self.weeklyGoal = weeklyGoal
        self.week = week
        self.liftedCount = liftedCount
        self.afterCount = afterCount
        self.updatedAt = updatedAt
    }
}

/// A care-team approved activity derived from pasted clinical notes or PT
/// instructions. The caregiver app may use AI or local rules to draft these,
/// but only approved items are written here and shown to the patient.
public struct CarePlanActivity: Identifiable, Codable, Equatable {
    public var id: String
    public var label: String
    public var sub: String
    public var title: String
    public var instruction: String
    public var symbol: String
    public var colorHex: String
    public var tintHex: String
    public var isPT: Bool
    public var valueTags: [String]
    public var effort: Int
    public var sourceNote: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                label: String,
                sub: String,
                title: String,
                instruction: String,
                symbol: String,
                colorHex: String,
                tintHex: String,
                isPT: Bool,
                valueTags: [String],
                effort: Int,
                sourceNote: String,
                createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.sub = sub
        self.title = title
        self.instruction = instruction
        self.symbol = symbol
        self.colorHex = colorHex
        self.tintHex = tintHex
        self.isPT = isPT
        self.valueTags = valueTags
        self.effort = effort
        self.sourceNote = sourceNote
        self.createdAt = createdAt
    }
}

/// The patient's self-built single-session plan, shared (with consent) so the
/// care team can see it. Written by Solace only when the patient enables
/// sharing on the plan summary screen.
public struct SSIPlanSummary: Codable {
    public var completedAt: Date
    public var topStruggle: String
    public var topHope: String
    public var actions: [String]
    public var supportPerson: String
    public var innerObstacle: String
    public var obstacleResponse: String
    /// 0–10 readiness, before and after the session. -1 = not collected.
    public var preReadiness: Int
    public var postReadiness: Int
    /// Summed 4-item hopelessness (4…16), before and after. -1 = not collected.
    public var preHopelessness: Int
    public var postHopelessness: Int

    public init(completedAt: Date, topStruggle: String, topHope: String,
                actions: [String], supportPerson: String,
                innerObstacle: String, obstacleResponse: String,
                preReadiness: Int, postReadiness: Int,
                preHopelessness: Int, postHopelessness: Int) {
        self.completedAt = completedAt
        self.topStruggle = topStruggle
        self.topHope = topHope
        self.actions = actions
        self.supportPerson = supportPerson
        self.innerObstacle = innerObstacle
        self.obstacleResponse = obstacleResponse
        self.preReadiness = preReadiness
        self.postReadiness = postReadiness
        self.preHopelessness = preHopelessness
        self.postHopelessness = postHopelessness
    }
}

/// A complete offline cache snapshot transported between the two devices.
public struct FirebaseCarePayload: Codable {
    public var snapshot: CareSnapshot?
    public var feed: [CareUpdate]
    public var carePlanActivities: [CarePlanActivity]
    public var curatedActivities: [CarePlanActivity]
    public var ssiPlan: SSIPlanSummary?
    public var caregiverMessages: [CaregiverMessage]
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case snapshot, feed, carePlanActivities, curatedActivities, ssiPlan, caregiverMessages, updatedAt
    }

    public init(snapshot: CareSnapshot?, feed: [CareUpdate],
                carePlanActivities: [CarePlanActivity],
                curatedActivities: [CarePlanActivity],
                ssiPlan: SSIPlanSummary?,
                caregiverMessages: [CaregiverMessage] = [],
                updatedAt: Date = Date()) {
        self.snapshot = snapshot
        self.feed = feed
        self.carePlanActivities = carePlanActivities
        self.curatedActivities = curatedActivities
        self.ssiPlan = ssiPlan
        self.caregiverMessages = caregiverMessages
        self.updatedAt = updatedAt
    }

    /// Older Firebase payloads did not contain messages. Treat that missing
    /// field as an empty inbox so an upgrade never breaks sync decoding.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        snapshot = try values.decodeIfPresent(CareSnapshot.self, forKey: .snapshot)
        feed = try values.decodeIfPresent([CareUpdate].self, forKey: .feed) ?? []
        carePlanActivities = try values.decodeIfPresent([CarePlanActivity].self, forKey: .carePlanActivities) ?? []
        curatedActivities = try values.decodeIfPresent([CarePlanActivity].self, forKey: .curatedActivities) ?? []
        ssiPlan = try values.decodeIfPresent(SSIPlanSummary.self, forKey: .ssiPlan)
        caregiverMessages = try values.decodeIfPresent([CaregiverMessage].self, forKey: .caregiverMessages) ?? []
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// The patient app's five built-in activities, mirrored here so the caregiver
/// app can offer them in the activity curator. Ids carry a "preset." prefix;
/// the patient app maps them back to the real built-ins (which keeps special
/// behavior like the tap-along rehab game).
public enum PresetCareActivities {
    public static let all: [CarePlanActivity] = [
        CarePlanActivity(id: "preset.call", label: "Call someone",
                         sub: "One person, a few minutes.", title: "Call someone",
                         instruction: "Pick one person, tap call, and keep it as short as you like.",
                         symbol: "phone.fill", colorHex: "4a7d78", tintHex: "dfecea",
                         isPT: false, valueTags: ["people"], effort: 1, sourceNote: "Preset"),
        CarePlanActivity(id: "preset.outside", label: "Sit outside",
                         sub: "Five minutes of fresh air.", title: "Sit outside",
                         instruction: "Find a chair near a window or door, and five minutes there is plenty.",
                         symbol: "sun.max", colorHex: "5f8a55", tintHex: "e4efdc",
                         isPT: false, valueTags: ["joy", "independent"], effort: 1, sourceNote: "Preset"),
        CarePlanActivity(id: "preset.pt", label: "Today's exercises",
                         sub: "Gentle taps, counted with you.", title: "Today's exercises",
                         instruction: "Tap each leaf as it appears, nice and easy, and five taps is the whole set.",
                         symbol: "figure.strengthtraining.traditional", colorHex: "3f6142", tintHex: "dfe9de",
                         isPT: true, valueTags: ["strength", "independent"], effort: 2, sourceNote: "Preset"),
        CarePlanActivity(id: "preset.music", label: "Listen to music",
                         sub: "One song you love.", title: "Listen to music",
                         instruction: "Put on one song that means something to you and just listen.",
                         symbol: "music.note", colorHex: "5a7590", tintHex: "e3eaf0",
                         isPT: false, valueTags: ["joy"], effort: 0, sourceNote: "Preset"),
        CarePlanActivity(id: "preset.photo", label: "Look at a photo",
                         sub: "Someone or somewhere good.", title: "Look at a photo",
                         instruction: "Open one photo that makes you smile and sit with it for a moment.",
                         symbol: "photo", colorHex: "8a6b7d", tintHex: "eee6eb",
                         isPT: false, valueTags: ["people", "joy"], effort: 0, sourceNote: "Preset"),
    ]
}

public enum SharedCareStore {
    private static let feedKey = "care.feed"
    private static let snapshotKey = "care.snapshot"
    private static let carePlanActivitiesKey = "care.plan.activities"
    private static let ssiPlanKey = "care.ssi.plan"
    private static let curatedKey = "care.curated.activities"
    private static let caregiverMessagesKey = "care.caregiver.messages"

    /// Removes all cross-app demo data. Used by the one-time simulator reset.
    public static func clearAll() {
        let defaults = SharedCare.defaults
        [feedKey, snapshotKey, carePlanActivitiesKey, ssiPlanKey, curatedKey, caregiverMessagesKey]
            .forEach { defaults.removeObject(forKey: $0) }
        // Keep an explicit empty feed marker so a normal relaunch does not
        // mistake a deliberate reset for a first launch and reseed history.
        writeFeed([])
    }

    public static func writeFeed(_ feed: [CareUpdate]) {
        if let data = try? JSONEncoder().encode(feed) {
            SharedCare.defaults.set(data, forKey: feedKey)
        }
    }

    public static var hasFeed: Bool {
        SharedCare.defaults.object(forKey: feedKey) != nil
    }

    public static func readFeed() -> [CareUpdate] {
        guard let data = SharedCare.defaults.data(forKey: feedKey),
              let feed = try? JSONDecoder().decode([CareUpdate].self, from: data) else { return [] }
        return feed
    }

    public static func writeCaregiverMessages(_ messages: [CaregiverMessage]) {
        if let data = try? JSONEncoder().encode(Array(messages.prefix(20))) {
            SharedCare.defaults.set(data, forKey: caregiverMessagesKey)
        }
    }

    public static func readCaregiverMessages() -> [CaregiverMessage] {
        guard let data = SharedCare.defaults.data(forKey: caregiverMessagesKey),
              let messages = try? JSONDecoder().decode([CaregiverMessage].self, from: data) else { return [] }
        return messages
    }

    public static func writeSnapshot(_ snapshot: CareSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            SharedCare.defaults.set(data, forKey: snapshotKey)
        }
    }

    public static func readSnapshot() -> CareSnapshot? {
        guard let data = SharedCare.defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(CareSnapshot.self, from: data) else { return nil }
        return snap
    }

    public static func writeCarePlanActivities(_ activities: [CarePlanActivity]) {
        if let data = try? JSONEncoder().encode(activities) {
            SharedCare.defaults.set(data, forKey: carePlanActivitiesKey)
        }
    }

    public static func readCarePlanActivities() -> [CarePlanActivity] {
        guard let data = SharedCare.defaults.data(forKey: carePlanActivitiesKey),
              let activities = try? JSONDecoder().decode([CarePlanActivity].self, from: data) else { return [] }
        return activities
    }

    /// The caregiver-arranged daily five. Empty/absent means the patient app
    /// keeps its automatic ordering (value + energy fit).
    public static func writeCuratedActivities(_ items: [CarePlanActivity]) {
        if let data = try? JSONEncoder().encode(items) {
            SharedCare.defaults.set(data, forKey: curatedKey)
        }
    }

    public static func readCuratedActivities() -> [CarePlanActivity] {
        guard let data = SharedCare.defaults.data(forKey: curatedKey),
              let items = try? JSONDecoder().decode([CarePlanActivity].self, from: data) else { return [] }
        return items
    }

    public static func clearCuratedActivities() {
        SharedCare.defaults.removeObject(forKey: curatedKey)
    }

    public static func writeSSIPlan(_ plan: SSIPlanSummary) {
        if let data = try? JSONEncoder().encode(plan) {
            SharedCare.defaults.set(data, forKey: ssiPlanKey)
        }
    }

    public static func clearSSIPlan() {
        SharedCare.defaults.removeObject(forKey: ssiPlanKey)
    }

    public static func readSSIPlan() -> SSIPlanSummary? {
        guard let data = SharedCare.defaults.data(forKey: ssiPlanKey),
              let plan = try? JSONDecoder().decode(SSIPlanSummary.self, from: data) else { return nil }
        return plan
    }
}
