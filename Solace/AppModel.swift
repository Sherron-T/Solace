import SwiftUI
import UIKit

/// A single day's dot in the 7-day trend chart.
struct WeekDot: Identifiable {
    let id: Int
    let color: Color
    let ring: Color
    let lift: CGFloat      // points the dot floats above the baseline (good = high)
    let label: String
    let isToday: Bool
    let isLogged: Bool
}

// MARK: - Accessibility preferences

enum WorkingHand: String { case left, right }

enum TextScale: String, CaseIterable, Identifiable {
    case comfortable, large, largest
    var id: String { rawValue }
    var multiplier: CGFloat {
        switch self {
        case .comfortable: return 1.0
        case .large:       return 1.18
        case .largest:     return 1.36
        }
    }
    var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .large:       return "Large"
        case .largest:     return "Largest"
        }
    }
}

/// The whole app is one observable state machine — mirrors the prototype's logic,
/// plus accessibility preferences, a single-session intervention, and the
/// behavioral-activation feedback loop (before/after mood re-check).
@MainActor
final class AppModel: ObservableObject {
    // Core state
    @Published var screen: Screen = .home
    @Published var mood: Int? = nil          // 0…4 or nil
    @Published var activity: String? = nil   // activity id or nil
    @Published var energy: Int? = nil        // 0…2 or nil (zero-type matrix, 2nd axis)
    @Published private(set) var carePlanActivities: [Activity] = []
    @Published private(set) var curatedActivities: [Activity] = []

    // Progress (persisted)
    @Published private(set) var streak: Int = 5
    @Published private(set) var wins: Int = 2
    @Published private(set) var week: [Int?] = [2, 3, 2, 3, 4, 3, nil]

    // Behavioral activation loop (persisted)
    @Published private(set) var plannedActivity: String? = nil   // saved-for-later id
    @Published private(set) var liftedCount: Int = 3             // times "I feel a bit better"
    @Published private(set) var afterCount: Int = 4              // times re-check answered
    @Published private(set) var lastAfter: AfterFeeling? = nil   // this session's answer

    // Single-session intervention (persisted)
    @Published private(set) var didBoost: Bool = false
    @Published private(set) var chosenValue: String? = nil       // PersonalValue id
    @Published private(set) var ssiActions: [String] = []        // patient's own plan actions

    // Caregiver bridge (persisted config; feed lives in CareBridge)
    let bridge: CareBridge
    @Published private(set) var patientName: String = "Sherron"
    @Published private(set) var careTeamName: String = "Maria"
    @Published private(set) var weeklyGoal: Int = 6
    @Published private(set) var reminderOn: Bool = true

    // Accessibility preferences (persisted)
    @Published private(set) var didOnboard: Bool = false
    @Published private(set) var workingHand: WorkingHand = .right
    @Published private(set) var textScale: TextScale = .comfortable
    @Published private(set) var preferPictures: Bool = false
    @Published private(set) var autoReadAloud: Bool = false
    @Published private(set) var autoVoiceInput: Bool = false   // hands-free listening
    @Published private(set) var neglectSide: NeglectSide = .none

    /// Bumped whenever a preference changes, so the view tree can rebuild and
    /// pick up the new global type scale / mirrored layout.
    @Published private(set) var settingsVersion: Int = 0
    @Published var showSettings: Bool = false

    // Live greeting and date (the old build showed a frozen seed date)
    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
    var dateStr: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private let store: UserDefaults
    private let publishesSharedState: Bool
    private var firebaseObserver: NSObjectProtocol?
    private var activityCompletionInFlight = false

    init(store: UserDefaults = .standard,
         bridge: CareBridge? = nil,
         publishesSharedState: Bool = true) {
        let resetSharedHistory = ProcessInfo.processInfo.arguments.contains("-reset-shared-history")
        self.store = store
        self.publishesSharedState = publishesSharedState
        self.bridge = bridge ?? CareBridge(persistenceEnabled: publishesSharedState,
                                           seedIfEmpty: !resetSharedHistory)
        if ProcessInfo.processInfo.arguments.contains("-reset-onboarding") {
            store.removeObject(forKey: "solace.didOnboard")
        }
        if resetSharedHistory {
            SharedCareStore.clearAll()
        }
        load()
        if ProcessInfo.processInfo.arguments.contains("-reset-onboarding") {
            didOnboard = false
            save()
        }
        rolloverIfNeeded()
        refreshCarePlanActivities()
        firebaseObserver = NotificationCenter.default.addObserver(
            forName: .firebaseCareStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCarePlanActivities()
            }
        }
    }

    deinit {
        if let firebaseObserver {
            NotificationCenter.default.removeObserver(firebaseObserver)
        }
    }

    var isRightHanded: Bool { workingHand == .right }

    // MARK: - Derived values

    var selectedMood: Mood? { Mood.at(mood) }
    var selectedEnergy: Energy? { Energy.at(energy) }
    var selectedActivity: Activity? { activity(with: activity) }
    var personalValue: PersonalValue? { PersonalValue.with(id: chosenValue) }
    /// Activities the patient chose for themselves in the single-session plan.
    var ssiActivities: [Activity] {
        ssiActions.enumerated().map { Activity.ssiAction($1, index: $0, valueID: chosenValue) }
    }

    var availableActivities: [Activity] {
        curatedActivities + carePlanActivities + ssiActivities + Activity.all
    }

    /// The week with today's just-logged mood reflected in, for trend/done views.
    private var liveWeek: [Int?] {
        var w = week
        if (screen == .trend || screen == .done), let m = mood {
            w[6] = m
        }
        return w
    }

    var weekDots: [WeekDot] {
        let cal = Calendar.current
        let letters = ["S", "M", "T", "W", "T", "F", "S"]   // Calendar weekday 1 = Sunday
        return liveWeek.enumerated().map { i, lvl in
            let isToday = i == 6
            let day = cal.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
            let label = isToday ? "Today" : letters[cal.component(.weekday, from: day) - 1]
            guard let lvl, let mo = Mood.at(lvl) else {
                return WeekDot(id: i, color: Token.borderChip, ring: Token.borderChip,
                               lift: 0, label: label, isToday: isToday, isLogged: false)
            }
            let lift = CGFloat((1 - mo.fill) * 70)
            return WeekDot(id: i,
                           color: mo.color,
                           ring: isToday ? Token.heading2 : mo.color,
                           lift: lift,
                           label: label,
                           isToday: isToday,
                           isLogged: true)
        }
    }

    /// True when the recent average mood is trending toward "Hard"/"Very low".
    var trendDown: Bool {
        let logged = liveWeek.compactMap { $0 }
        let recent = logged.suffix(4)
        guard !recent.isEmpty else { return false }
        let avg = Double(recent.reduce(0, +)) / Double(recent.count)
        return avg >= 2.6
    }

    /// 0…1 progress for the Done-screen ring.
    var ringProgress: Double { min(Double(streak) / 7.0, 1.0) }

    var streakCount: Int { streak }
    var winsThisWeek: Int { wins }

    var doneMessage: String {
        var base: String
        if let a = selectedActivity, a.isPT {
            base = "That’s a rehab win, logged for your care team."
        } else {
            base = "Showing up for yourself today was the hard part."
        }
        switch lastAfter {
        case .better: base += " And it gave you a little lift."
        case .hard:   base += " Some days it doesn’t lift right away, and doing it still counts."
        default:      break
        }
        return base
    }

    /// Activities sorted so the best fits float up: value matches first, then
    /// effort matched to today's energy (tired -> restful first, energetic -> active first).
    var orderedActivities: [Activity] {
        // When the care team arranged the daily five, their order stands.
        if !curatedActivities.isEmpty {
            return Array(curatedActivities.prefix(5))
        }
        let v = chosenValue
        let e = energy
        func score(_ a: Activity) -> Int {
            var s = 0
            if a.isCarePlan { s += 8 }
            if a.id.hasPrefix("ssi.") { s += 9 }   // the patient's own plan leads
            if let v, a.valueTags.contains(v) { s += 10 }
            if let e {
                switch e {
                case 0: s += (2 - a.effort)          // tired: restful wins
                case 2: s += a.effort                // energetic: active wins
                default: break
                }
            }
            return s
        }
        return Array(availableActivities.enumerated()
            .sorted { (l, r) in
                let sl = score(l.element), sr = score(r.element)
                return sl != sr ? sl > sr : l.offset < r.offset   // stable
            }
            .map(\.element)
            .prefix(5))
    }

    /// True when the chosen activity serves the user's stated value.
    var activityMatchesValue: Bool {
        guard let a = selectedActivity, let v = chosenValue else { return false }
        return a.valueTags.contains(v)
    }

    // MARK: - Navigation / actions

    func openMood()      { go(.mood) }
    func goHome()        { refreshCarePlanActivities(); go(.home) }
    func goActivities()  { refreshCarePlanActivities(); go(.activities) }
    func goTrend()       { go(.trend) }
    func openSafety()    { go(.safety) }
    func openBoost()     { showSettings = false; go(.boost) }

    /// Screen-level Back behavior used by the shared voice-navigation layer.
    /// SSI overrides Back with its own stage history before this is consulted.
    func voiceGoBack() {
        switch screen {
        case .home:       break
        case .mood:       goHome()
        case .energy:     openMood()
        case .confirm:    go(.energy)
        case .activities: goHome()
        case .doing:      goActivities()
        case .rehabGame:  goActivities()
        case .after:      go(.doing)
        case .done:       goHome()
        case .trend:      goHome()
        case .safety:     goHome()
        case .boost:      goHome()
        }
    }

    func selectMood(_ index: Int) {
        Haptics.light()
        mood = index
    }

    func confirmMood() {
        // "Very low" routes straight to the human / crisis path.
        if mood == 4 { go(.safety) } else { go(.energy) }
    }

    /// One-shot spoken check-in: free speech condensed to mood (+ energy when
    /// heard). "Very low" still routes to the human path; when energy wasn't
    /// heard, the energy screen asks as usual.
    func voiceCheckin(mood moodIndex: Int, energy energyIndex: Int?) {
        selectMood(moodIndex)
        if moodIndex == 4 { go(.safety); return }
        if let energyIndex {
            selectEnergy(energyIndex)   // records, notifies the bridge, → confirm
        } else {
            go(.energy)
        }
    }

    /// Second axis of the zero-type matrix. Skippable (nil).
    func selectEnergy(_ index: Int?) {
        if index != nil { Haptics.light() }
        energy = index
        if let m = selectedMood {
            bridge.synthesizeCheckin(patientName: patientName, mood: m, energy: selectedEnergy)
        }
        go(.confirm)
    }

    /// "Today's exercises" runs as a tap-along micro-rehab game.
    func startRehabGame() { go(.rehabGame) }

    func pick(activity id: String) {
        activity = id
        activityCompletionInFlight = false
        go(.doing)
    }

    /// "I did it" — celebrate lightly, then ask how it felt (the BA loop).
    func finishActivity() {
        guard [.doing, .rehabGame].contains(screen), !activityCompletionInFlight else { return }
        activityCompletionInFlight = true
        Haptics.success()
        go(.after)
    }

    /// Save the open activity for later today instead of doing it now.
    func planForLater() {
        plannedActivity = activity
        save()
        go(.home)
    }

    /// Resume a saved plan from the home screen.
    func startPlanned() {
        refreshCarePlanActivities()
        guard let id = plannedActivity else { return }
        activity = id
        go(.doing)
    }

    /// Record the post-activity re-check (or nil if skipped) and complete.
    func recordAfter(_ feeling: AfterFeeling?) {
        if let feeling {
            afterCount += 1
            if feeling == .better { liftedCount += 1 }
            lastAfter = feeling
        } else {
            lastAfter = nil
        }
        completeActivity()
    }

    func activity(with id: String?) -> Activity? {
        guard let id else { return nil }
        return availableActivities.first { $0.id == id }
    }

    func refreshCarePlanActivities() {
        carePlanActivities = SharedCareStore.readCarePlanActivities().map(Activity.carePlan)
        curatedActivities = SharedCareStore.readCuratedActivities().compactMap(resolveCurated)
        if let plannedActivity, activity(with: plannedActivity) == nil {
            self.plannedActivity = nil
            save()
        }
    }

    /// A curated entry can point at a built-in preset, one of the patient's own
    /// plan actions, or a care-plan item. Mapping back to the real activity
    /// keeps special behavior (like the tap-along rehab game) intact.
    private func resolveCurated(_ item: CarePlanActivity) -> Activity? {
        if item.id.hasPrefix("preset.") {
            return Activity.with(id: String(item.id.dropFirst("preset.".count)))
        }
        if item.id.hasPrefix("ssi."),
           let index = Int(item.id.dropFirst("ssi.".count)),
           ssiActions.indices.contains(index) {
            return Activity.ssiAction(ssiActions[index], index: index, valueID: chosenValue)
        }
        return Activity.carePlan(item)
    }

    private func completeActivity() {
        if let a = selectedActivity {
            bridge.synthesizeCompletion(patientName: patientName, activity: a, after: lastAfter)
        }
        wins += 1
        if week[6] == nil { streak += 1 }        // first completion today bumps the streak
        if let m = mood { week[6] = m }          // log today's mood
        if plannedActivity == activity { plannedActivity = nil }
        save()
        activityCompletionInFlight = false
        go(.done)
    }

    // MARK: - Demo reset (hidden gesture in Settings)
    //
    // Restores the seeded demo state without reinstalling, so permission
    // dialogs never re-trigger mid-demo. Accessibility preferences and
    // onboarding stay untouched.

    func resetDemo() {
        streak = 5
        wins = 2
        week = [2, 3, 2, 3, 4, 3, nil]
        plannedActivity = nil
        liftedCount = 3
        afterCount = 4
        lastAfter = nil
        didBoost = false
        chosenValue = nil
        ssiActions = []
        mood = nil
        energy = nil
        activity = nil
        store.removeObject(forKey: Key.ssiResponse)
        store.set(Calendar.current.startOfDay(for: Date()), forKey: Key.lastOpen)

        SharedCareStore.writeCarePlanActivities([])
        SharedCareStore.clearCuratedActivities()
        SharedCareStore.clearSSIPlan()
        bridge.resetToSeed(patientName: patientName)

        refreshCarePlanActivities()
        save()
        Haptics.soft()
        showSettings = false
        go(.home)
    }

    /// Secret hackathon-only fixture, reached by holding the Settings title.
    /// It changes demo data only; accessibility and permission choices remain.
    func loadHackathonCareBridgeHistory() {
        streak = 7
        wins = 5
        week = [1, 2, 1, 3, 2, 1, nil]
        liftedCount = 4
        afterCount = 5
        mood = nil
        energy = nil
        activity = nil
        store.set(Calendar.current.startOfDay(for: Date()), forKey: Key.lastOpen)
        bridge.seedDemoHistory(patientName: patientName)
        save()
        Haptics.success()
    }

    // MARK: - Day rollover
    //
    // On a new calendar day the 7-day window slides and today opens fresh.
    // The streak HOLDS across gaps (no-failure rule: missing a day never
    // punishes); weekly wins reset when a new week starts. The first launch
    // keeps the seeded demo week intact.

    func rolloverIfNeeded() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let last = store.object(forKey: Key.lastOpen) as? Date
        store.set(today, forKey: Key.lastOpen)
        guard let last else { return }

        let lastDay = cal.startOfDay(for: last)
        let days = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
        guard days > 0 else { return }

        for _ in 0..<min(days, 7) {
            week.removeFirst()
            week.append(nil)
        }
        if days >= 7 || !cal.isDate(last, equalTo: Date(), toGranularity: .weekOfYear) {
            wins = 0
        }
        save()
    }

    // MARK: - Caregiver configuration (heavy config lives on the caregiver side)

    func setWeeklyGoal(_ n: Int) { weeklyGoal = max(1, min(14, n)); save() }
    func setReminder(_ on: Bool) {
        reminderOn = on
        if on { GentleReminder.enable() } else { GentleReminder.disable() }
        save()
    }
    func setPatientName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        patientName = trimmed.isEmpty ? "Sherron" : trimmed
        save()
    }
    func setCareTeamName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        careTeamName = trimmed.isEmpty ? "Maria" : trimmed
        save()
    }

    // MARK: - Single-session intervention

    /// Autosaved after every SSI screen so leaving mid-session loses nothing.
    func autosaveSSI(_ response: SSIResponse) {
        if let data = try? JSONEncoder().encode(response) {
            store.set(data, forKey: Key.ssiResponse)
        }
    }

    func savedSSIDraft() -> SSIResponse? {
        guard !didBoost,
              let data = store.data(forKey: Key.ssiResponse),
              let draft = try? JSONDecoder().decode(SSIResponse.self, from: data) else { return nil }
        return draft
    }

    /// Finish the SSI: keep the plan, personalize the app around the chosen
    /// hope, feed the two actions into daily activities, and (with consent)
    /// share the plan summary with the care team.
    func completeSSI(_ response: SSIResponse, goToPlan: Bool) {
        var final = response
        final.completedAt = Date()
        autosaveSSI(final)

        didBoost = true
        chosenValue = final.impliedValueID
        ssiActions = [final.selfCareAction1, final.selfCareAction2].compactMap { $0 }

        if final.sharedWithCareTeam {
            SharedCareStore.writeSSIPlan(SSIPlanSummary(
                completedAt: final.completedAt ?? Date(),
                topStruggle: final.topStruggle ?? "",
                topHope: final.topHope ?? "",
                actions: ssiActions,
                supportPerson: final.supportPerson ?? "Not sure yet",
                innerObstacle: final.innerObstacle ?? "",
                obstacleResponse: final.obstacleResponse ?? "",
                preReadiness: final.preReadiness ?? -1,
                postReadiness: final.postReadiness ?? -1,
                preHopelessness: final.preHopelessnessSum,
                postHopelessness: final.postHopelessnessSum
            ))
            bridge.post("\(patientName) built a self-guided plan: two small actions and an if/then coping step.",
                        kind: "activity")
        }

        save()
        Haptics.soft()
        if goToPlan { goActivities() } else { go(.home) }
    }

    private func go(_ s: Screen) {
        if UIAccessibility.isReduceMotionEnabled {
            screen = s
        } else {
            withAnimation(.easeOut(duration: 0.38)) { screen = s }
        }
    }

    // MARK: - Preferences

    func completeOnboarding(hand: WorkingHand, text: TextScale, pictures: Bool,
                            readAloud: Bool, neglect: NeglectSide = .none,
                            autoVoice: Bool = false) {
        workingHand = hand
        textScale = text
        preferPictures = pictures
        autoReadAloud = readAloud
        autoVoiceInput = autoVoice
        neglectSide = neglect
        didOnboard = true
        applyTypography()
        bumpSettings()
        save()
    }

    func setWorkingHand(_ h: WorkingHand) { workingHand = h; bumpSettings(); save() }
    func setTextScale(_ t: TextScale) { textScale = t; applyTypography(); bumpSettings(); save() }
    func setPreferPictures(_ v: Bool) { preferPictures = v; bumpSettings(); save() }
    func setAutoReadAloud(_ v: Bool) { autoReadAloud = v; bumpSettings(); save() }
    func setAutoVoiceInput(_ v: Bool) { autoVoiceInput = v; save() }
    func setNeglectSide(_ s: NeglectSide) { neglectSide = s; bumpSettings(); save() }

    func replayOnboarding() {
        didOnboard = false
        showSettings = false
        bumpSettings()
        save()
    }

    private func applyTypography() { AppType.scale = textScale.multiplier }
    private func bumpSettings() { settingsVersion += 1 }

    // MARK: - Persistence (offline-first, nothing lost on leaving)

    private enum Key {
        static let streak = "solace.streak"
        static let wins   = "solace.wins"
        static let week   = "solace.week"
        static let didOnboard = "solace.didOnboard"
        static let hand   = "solace.hand"
        static let textScale = "solace.textScale"
        static let pictures = "solace.pictures"
        static let readAloud = "solace.readAloud"
        static let autoVoice = "solace.autoVoice"
        static let neglect = "solace.neglect"
        static let planned = "solace.planned"
        static let lifted = "solace.lifted"
        static let afterCount = "solace.afterCount"
        static let didBoost = "solace.didBoost"
        static let value = "solace.value"
        static let ssiResponse = "solace.ssi.response"
        static let ssiActions = "solace.ssi.actions"
        static let lastOpen = "solace.lastOpenDay"
        static let patientName = "solace.patientName"
        static let careTeamName = "solace.careTeamName"
        static let weeklyGoal = "solace.weeklyGoal"
        static let reminderOn = "solace.reminderOn"
    }

    private func save() {
        store.set(streak, forKey: Key.streak)
        store.set(wins, forKey: Key.wins)
        // Encode nil as -1 so the 7-slot shape is preserved.
        store.set(week.map { $0 ?? -1 }, forKey: Key.week)
        store.set(didOnboard, forKey: Key.didOnboard)
        store.set(workingHand.rawValue, forKey: Key.hand)
        store.set(textScale.rawValue, forKey: Key.textScale)
        store.set(preferPictures, forKey: Key.pictures)
        store.set(autoReadAloud, forKey: Key.readAloud)
        store.set(autoVoiceInput, forKey: Key.autoVoice)
        store.set(neglectSide.rawValue, forKey: Key.neglect)
        store.set(plannedActivity, forKey: Key.planned)
        store.set(liftedCount, forKey: Key.lifted)
        store.set(afterCount, forKey: Key.afterCount)
        store.set(didBoost, forKey: Key.didBoost)
        store.set(chosenValue, forKey: Key.value)
        store.set(ssiActions, forKey: Key.ssiActions)
        store.set(patientName, forKey: Key.patientName)
        store.set(careTeamName, forKey: Key.careTeamName)
        store.set(weeklyGoal, forKey: Key.weeklyGoal)
        store.set(reminderOn, forKey: Key.reminderOn)
        publishSnapshot()
    }

    /// Mirror rolled-up status into the App Group so the SolaceCare app sees it live.
    private func publishSnapshot() {
        guard publishesSharedState else { return }
        SharedCareStore.writeSnapshot(CareSnapshot(
            patientName: patientName,
            streak: streak,
            wins: wins,
            weeklyGoal: weeklyGoal,
            week: week.map { $0 ?? -1 },
            liftedCount: liftedCount,
            afterCount: afterCount
        ))
        Task { await FirebaseSync.shared.publishCurrentState() }
    }

    private func load() {
        if store.object(forKey: Key.streak) != nil { streak = store.integer(forKey: Key.streak) }
        if store.object(forKey: Key.wins) != nil { wins = store.integer(forKey: Key.wins) }
        if let raw = store.array(forKey: Key.week) as? [Int], raw.count == 7 {
            week = raw.map { $0 < 0 ? nil : $0 }
        }
        didOnboard = store.bool(forKey: Key.didOnboard)
        if let h = store.string(forKey: Key.hand), let hand = WorkingHand(rawValue: h) { workingHand = hand }
        if let t = store.string(forKey: Key.textScale), let scale = TextScale(rawValue: t) { textScale = scale }
        preferPictures = store.bool(forKey: Key.pictures)
        autoReadAloud = store.bool(forKey: Key.readAloud)
        autoVoiceInput = store.bool(forKey: Key.autoVoice)
        if let n = store.string(forKey: Key.neglect), let side = NeglectSide(rawValue: n) { neglectSide = side }
        plannedActivity = store.string(forKey: Key.planned)
        if store.object(forKey: Key.lifted) != nil { liftedCount = store.integer(forKey: Key.lifted) }
        if store.object(forKey: Key.afterCount) != nil { afterCount = store.integer(forKey: Key.afterCount) }
        didBoost = store.bool(forKey: Key.didBoost)
        chosenValue = store.string(forKey: Key.value)
        if let actions = store.array(forKey: Key.ssiActions) as? [String] { ssiActions = actions }
        if let n = store.string(forKey: Key.patientName) { patientName = n }
        if let n = store.string(forKey: Key.careTeamName) { careTeamName = n }
        if store.object(forKey: Key.weeklyGoal) != nil { weeklyGoal = store.integer(forKey: Key.weeklyGoal) }
        if store.object(forKey: Key.reminderOn) != nil { reminderOn = store.bool(forKey: Key.reminderOn) }
        applyTypography()
        publishSnapshot()
    }
}
