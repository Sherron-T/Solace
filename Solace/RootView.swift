import SwiftUI

/// The single-screen state machine over a botanical-glass gradient shell.
/// Home/Activities/Safety get the persistent thumb-zone tab bar; flow screens
/// (mood, doing, game…) stay full-bleed and distraction-free.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var handsFree: HandsFreeController
    @EnvironmentObject private var narrator: Narrator
    @Environment(\.scenePhase) private var scenePhase

    /// Screens that show the bottom tab bar.
    private var showsTabBar: Bool {
        model.didOnboard && [.home, .activities, .safety].contains(model.screen)
    }

    private var showsVoiceNavigationStatus: Bool {
        model.didOnboard && model.autoVoiceInput && !model.showSettings &&
        model.screen != .safety && ![.mood, .energy, .boost].contains(model.screen)
    }

    var body: some View {
        ZStack {
            Token.shellGradient.ignoresSafeArea()
            if model.screen == .safety {
                Token.safetyBG.opacity(0.55).ignoresSafeArea()
            }

            if !model.didOnboard {
                OnboardingView()
                    .transition(.opacity)
            } else {
                Group {
                    switch model.screen {
                    case .home:       HomeView()
                    case .mood:       MoodView()
                    case .energy:     EnergyView()
                    case .confirm:    ConfirmView()
                    case .activities: ActivitiesView()
                    case .doing:      DoingView()
                    case .rehabGame:  RehabGameView()
                    case .after:      AfterCheckView()
                    case .done:       DoneView()
                    case .trend:      TrendView()
                    case .safety:     SafetyView()
                    case .boost:      SSIView()
                    }
                }
                // Rebuild on screen OR preference change (new type scale / mirror).
                .id("\(screenID)-\(model.settingsVersion)")
                // Visuospatial-neglect anchoring: bright cue on the missed side,
                // content shifted toward the intact field.
                .neglectAnchor(model.neglectSide)
            }
        }
        // The tab bar lives OUTSIDE the switching subtree, so it stays put
        // (same position, no re-animation) across Home/Activities/Safety.
        .safeAreaInset(edge: .bottom) {
            if showsTabBar { SolaceTabBar() }
        }
        .overlay(alignment: .bottom) {
            if showsVoiceNavigationStatus {
                HandsFreeNavigationIndicator()
                    .padding(.horizontal, 22)
                    .padding(.bottom, showsTabBar ? 78 : 12)
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        // Re-assert the daily reminder each launch (covers reinstalls/reboots);
        // prompts for permission the first time.
        .onAppear {
            if model.didOnboard && model.reminderOn { GentleReminder.enable() }
            NotificationPresenter.shared.onTap = { [weak model] in
                guard let model, model.didOnboard else { return }
                model.openMood()
            }
            installVoiceCommands()
            configureVoiceNavigation()
        }
        // Catch the midnight crossing when the app stays open overnight.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.rolloverIfNeeded()
                configureVoiceNavigation()
                handsFree.resume()
            } else {
                handsFree.suspend()
            }
        }
        .onChange(of: model.screen) { _, _ in
            configureVoiceNavigation()
        }
        .onChange(of: model.showSettings) { _, isShowing in
            if isShowing {
                handsFree.suspend()
            } else {
                configureVoiceNavigation()
                handsFree.resume()
            }
        }
        .onChange(of: model.didOnboard) { _, didOnboard in
            if !didOnboard {
                handsFree.stop()
            } else {
                installVoiceCommands()
                configureVoiceNavigation()
            }
        }
        .onChange(of: model.autoVoiceInput) { _, _ in
            configureVoiceNavigation()
        }
    }

    private func installVoiceCommands() {
        handsFree.onVoiceCommand = { [weak model, weak narrator] command in
            // Onboarding runs its own capture; destination commands must never
            // steer the app behind the setup flow.
            guard let model, let narrator, model.didOnboard else { return true }
            switch command {
            case .repeatPrompt:
                narrator.repeatLast()
            case .goBack:
                model.voiceGoBack()
            case .stopListening:
                return true // The controller pauses itself before this handler.
            case .help:
                model.openSafety()
            case .home:
                model.goHome()
            case .activities:
                model.goActivities()
            case .trends:
                model.goTrend()
            case .checkIn:
                model.openMood()
            case .settings:
                model.showSettings = true
            }
            return true
        }
    }

    private func configureVoiceNavigation() {
        guard model.didOnboard,
              model.autoVoiceInput,
              !model.showSettings,
              model.screen != .safety else {
            handsFree.setNavigationConfiguration(nil)
            return
        }

        handsFree.setNavigationConfiguration(HandsFreeCaptureConfiguration(
            id: "navigation.\(screenID)",
            hint: "Say home, back, repeat, help, or another destination",
            autoStart: true,
            continuous: true,
            earlyFinish: { HandsFreeVoiceCommand.fuzzyParse($0) != nil }
        ) { [weak handsFree] heard in
            guard let command = await Self.navigationCommand(from: heard) else {
                // Overheard conversation stays inert; only short, command-like
                // utterances earn the spoken hint.
                guard heard.split(separator: " ").count <= 4 else { return .complete }
                return .confirming("Try saying home, back, repeat, activities, trends, check in, settings, help, or stop.") {}
            }

            switch command {
            case .stopListening:
                return .confirming("Voice navigation paused.") {
                    handsFree?.pause()
                }
            case .repeatPrompt:
                return HandsFreeTranscriptResult(confirmation: nil,
                                                 confirmationDelayNanoseconds: 0) {
                    _ = handsFree?.onVoiceCommand?(.repeatPrompt)
                }
            default:
                return .confirming(Self.acknowledgement(for: command)) {
                    _ = handsFree?.onVoiceCommand?(command)
                }
            }
        })
    }

    /// Free speech onto a destination, cheapest tier first: conservative fuzzy
    /// phrases, then the same on-device Apple Intelligence option matching the
    /// answer screens use ("I want to see how my week went" → trends).
    private static func navigationCommand(from heard: String) async -> HandsFreeVoiceCommand? {
        if let fuzzy = HandsFreeVoiceCommand.fuzzyParse(heard) { return fuzzy }
        // Model matching is comparatively expensive; reserve it for utterances
        // that plausibly are a request (single stray words and long overheard
        // sentences never reach it).
        let wordCount = heard.split(separator: " ").count
        guard (2...8).contains(wordCount) else { return nil }
        guard let match = await SSIVoiceInterpreter.pickOption(heard, options: navigationOptions.map(\.label)) else {
            return nil
        }
        return navigationOptions.first { $0.label == match }?.command
    }

    private static let navigationOptions: [(label: String, command: HandsFreeVoiceCommand)] = [
        ("go to the home screen", .home),
        ("go back to the previous screen", .goBack),
        ("repeat that again", .repeatPrompt),
        ("open the list of activities", .activities),
        ("show my week of trends", .trends),
        ("start a mood check in", .checkIn),
        ("open the settings", .settings),
        ("get help and support", .help),
        ("stop listening", .stopListening),
    ]

    private static func acknowledgement(for command: HandsFreeVoiceCommand) -> String {
        switch command {
        case .home: return "Going home."
        case .goBack: return "Going back."
        case .activities: return "Opening activities."
        case .trends: return "Opening your week."
        case .checkIn: return "Starting your check in."
        case .settings: return "Opening settings."
        case .help: return "Opening support."
        case .repeatPrompt, .stopListening: return ""
        }
    }

    private var screenID: String {
        switch model.screen {
        case .home: return "home"
        case .mood: return "mood"
        case .energy: return "energy"
        case .confirm: return "confirm"
        case .activities: return "activities"
        case .doing: return "doing-\(model.activity ?? "")"
        case .rehabGame: return "rehabGame"
        case .after: return "after"
        case .done: return "done"
        case .trend: return "trend"
        case .safety: return "safety"
        case .boost: return "boost"
        }
    }
}
