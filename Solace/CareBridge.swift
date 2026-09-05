import Foundation

// MARK: - Care bridge (patient-side writer)
//
// Translates patient taps into plain-language updates ("status synthesizer")
// and publishes them through SharedCareStore — the App Group container the
// separate SolaceCare caregiver app reads live. CareUpdate/CareSnapshot live
// in Shared/SharedCare.swift, compiled into both apps.

@MainActor
final class CareBridge: ObservableObject {
    @Published private(set) var feed: [CareUpdate] = []
    @Published private(set) var caregiverMessages: [CaregiverMessage] = []
    @Published private(set) var unreadCaregiverMessages: [CaregiverMessage] = []
    private let persistenceEnabled: Bool
    private let readMessageIDsKey = "solace.readCaregiverMessageIDs"

    init(persistenceEnabled: Bool = true, seedIfEmpty: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
        feed = persistenceEnabled ? SharedCareStore.readFeed() : []
        caregiverMessages = persistenceEnabled ? SharedCareStore.readCaregiverMessages() : []
        updateUnreadMessages()
        if feed.isEmpty && seedIfEmpty && !SharedCareStore.hasFeed { seed() }
    }

    /// Refreshes caregiver-authored messages after Firebase or the App Group
    /// cache receives a new payload.
    func refreshCaregiverMessages() {
        guard persistenceEnabled else { return }
        caregiverMessages = SharedCareStore.readCaregiverMessages()
        updateUnreadMessages()
    }

    func markCaregiverMessageRead(_ message: CaregiverMessage) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: readMessageIDsKey) ?? [])
        ids.insert(message.id.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: readMessageIDsKey)
        updateUnreadMessages()
    }

    private func updateUnreadMessages() {
        let readIDs = Set(UserDefaults.standard.stringArray(forKey: readMessageIDsKey) ?? [])
        unreadCaregiverMessages = caregiverMessages.filter { !readIDs.contains($0.id.uuidString) }
    }

    func post(_ text: String, kind: String) {
        feed.insert(CareUpdate(text: text, kind: kind), at: 0)
        if feed.count > 50 { feed = Array(feed.prefix(50)) }
        if persistenceEnabled {
            SharedCareStore.writeFeed(feed)
            Task { await FirebaseSync.shared.publishCurrentState() }
        }
    }

    /// One shareable plain-language digest of the most recent updates —
    /// what gets sent to the family thread.
    func digest(patientName: String) -> String {
        let recent = feed.prefix(3).reversed().map { "• " + $0.text }
        let body = recent.isEmpty ? "No check-ins yet today." : recent.joined(separator: "\n")
        return "Update on \(patientName) from Solace:\n\(body)"
    }

    // MARK: Status synthesizer — taps in, sentences out

    func synthesizeCheckin(patientName: String, mood: Mood, energy: Energy?) {
        var s = "\(patientName) checked in, feeling \(mood.word.lowercased())"
        if let energy { s += ", \(energy.phrase)" }
        s += "."
        post(s, kind: "checkin")
    }

    func synthesizeCompletion(patientName: String, activity: Activity, after: AfterFeeling?) {
        var s = "\(patientName) completed “\(activity.label)”"
        if activity.isPT { s += ", a rehab win" }
        switch after {
        case .better: s += ", and says it helped a bit"
        case .hard:   s += ". Still a hard day"
        default:      break
        }
        s += "."
        post(s, kind: activity.isPT ? "rehab" : "activity")
    }

    /// Wipe the feed back to the demo seed (used by the hidden demo reset).
    func resetToSeed(patientName: String = "Sherron") {
        feed = []
        seed(patientName: patientName)
    }

    /// Hidden hackathon fixture: a realistic, date-spread feed that makes it
    /// possible to inspect CareBridge grouping, summaries, and relative dates
    /// without waiting a week in real time.
    func seedDemoHistory(patientName: String,
                         now: Date = Date(),
                         calendar: Calendar = .current) {
        func day(_ offset: Int, hour: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }

        feed = [
            CareUpdate(text: "\(patientName) completed “Sit outside”, and says it helped a bit.",
                       kind: "activity", date: day(-1, hour: 15)),
            CareUpdate(text: "\(patientName) checked in, feeling okay, energy is steady.",
                       kind: "checkin", date: day(-1, hour: 9)),
            CareUpdate(text: "\(patientName) completed “Today's exercises”, a rehab win.",
                       kind: "rehab", date: day(-2, hour: 14)),
            CareUpdate(text: "\(patientName) checked in, feeling low, energy is low.",
                       kind: "checkin", date: day(-2, hour: 9)),
            CareUpdate(text: "\(patientName) completed “Call someone”, and says it helped a bit.",
                       kind: "activity", date: day(-3, hour: 16)),
            CareUpdate(text: "\(patientName) checked in, feeling hard, energy is low.",
                       kind: "checkin", date: day(-3, hour: 10)),
            CareUpdate(text: "\(patientName) completed “Listen to music”, and says it helped a bit.",
                       kind: "activity", date: day(-4, hour: 13)),
            CareUpdate(text: "\(patientName) checked in, feeling okay, energy is steady.",
                       kind: "checkin", date: day(-4, hour: 9)),
            CareUpdate(text: "\(patientName) checked in, feeling low, energy is steady.",
                       kind: "checkin", date: day(-5, hour: 9)),
            CareUpdate(text: "\(patientName) completed “Look at a photo”, and says it helped a bit.",
                       kind: "activity", date: day(-6, hour: 17)),
            CareUpdate(text: "\(patientName) checked in, feeling okay, energy is good.",
                       kind: "checkin", date: day(-6, hour: 8)),
            CareUpdate(text: "\(patientName) checked in, feeling good, energy is steady.",
                       kind: "checkin", date: day(-7, hour: 9)),
        ]
        if persistenceEnabled { SharedCareStore.writeFeed(feed) }
    }

    /// Demo seed so the caregiver feed isn't empty on first open.
    private func seed(patientName: String = "Sherron") {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        feed = [
            CareUpdate(text: "\(patientName) completed “Sit outside”, and says it helped a bit.",
                       kind: "activity", date: yesterday),
            CareUpdate(text: "\(patientName) checked in, feeling okay, energy is steady.",
                       kind: "checkin", date: yesterday),
        ]
        if persistenceEnabled { SharedCareStore.writeFeed(feed) }
    }
}
