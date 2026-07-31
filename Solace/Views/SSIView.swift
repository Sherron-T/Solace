import SwiftUI

/// The single-session intervention — a ~5-minute, science-informed flow
/// (see SSIModels.swift for structure and evidence references).
/// One question per screen, large targets, no typing required, support one
/// tap away on every screen, progress autosaved after every step.
struct SSIView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var handsFree: HandsFreeController

    @State private var navigation = SSIStageHistory()
    @State private var voiceNote: String? = nil

    @State private var response = SSIResponse()

    // Per-stage scratch state, loaded/committed on navigation.
    @State private var picks: Set<String> = []
    @State private var otherText: String = ""
    @State private var scalePick: Int? = nil
    @State private var dialValue: Int? = nil
    @State private var supportText: String = ""
    @State private var breathCycles: Int = 0

    private var stage: SSIStage { navigation.stage }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(speak: spoken) { goBack() }
                .padding(.horizontal, 22)

            progressBar
                .padding(.horizontal, 26)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 22) {
                    content
                    if stageTakesVoice {
                        HandsFreeCapturePill()
                        if let voiceNote {
                            Text(voiceNote)
                                .font(.ui(12.5, .medium))
                                .foregroundStyle(Token.body)
                                .multilineTextAlignment(.center)
                        }
                    } else if model.autoVoiceInput {
                        HandsFreeNavigationIndicator()
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .padding(.top, 14)
        .padding(.bottom, 30)
        .id(stage)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(stageTakesVoice ? voiceConfiguration : navigationVoiceConfiguration)
        .onAppear {
            restoreDraft()
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Token.borderCard)
                Capsule().fill(Token.primary)
                    .frame(width: max(8, geo.size.width * stage.progress))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Step progress: \(Int(stage.progress * 100)) percent")
    }

    // MARK: Stage content

    @ViewBuilder private var content: some View {
        switch stage {
        case .landing:
            iconTile("map.fill", Token.primary, Token.accentTint)
            heading("Build one small plan for today.",
                    "This takes about 5 minutes, you can stop any time, and nothing is lost.")
            infoNote("If sharing is on, your care team can see the plan you make. You choose at the end.")

        case .consent:
            iconTile("hand.raised.fill", Token.sage, Token.sageCard)
            heading("Before we start",
                    "Your answers stay on this phone. At the end you can choose to share your plan with your care team, or not.\n\nThis is support, not emergency care. If you need help right now, the support button below is always there.")

        case .preHope1, .preHope2, .preHope3, .preHope4:
            heading("Does this feel true right now?", SSIOptions.hopelessnessItems[hopeIndex(stage)])
            AgreeScale(value: $scalePick)

        case .safetyOffer:
            iconTile("heart.fill", Token.urgent, Token.warmAlertCard)
            heading("That sounds heavy.",
                    "Thank you for being honest, that takes strength. You don't have to carry this alone. Would you like to see support options first? The plan will wait for you.")
            Button { model.openSafety() } label: {
                Text("See support options")
                    .font(.ui(17, .bold))
                    .foregroundStyle(Token.urgent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Token.warmAlertCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Token.borderWarm, lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())

        case .preReadiness:
            heading("How ready do you feel to take one small step for your mental health right now?", nil)
            NumberDial(value: $dialValue, range: 0...10,
                       lowAnchor: "Not ready", highAnchor: "Very ready")

        case .psychoedCommon:
            iconTile("person.2.fill", Token.sage, Token.sageCard)
            heading("Recovery can feel lonely.",
                    "Mood changes after a stroke are common. About 1 in 3 survivors go through this.")

        case .psychoedStuck:
            iconTile("cloud.fill", Color(hex: "5a7590"), Color(hex: "e3eaf0"))
            heading("Feeling stuck makes everything harder.",
                    "Low mood can make rehab, meals, rest, and reaching out feel out of reach. That's the low mood talking, not you.")

        case .psychoedNoFault:
            iconTile("checkmark.shield.fill", Token.primary, Token.accentTint)
            heading("This is not a personal failure.",
                    "It's part of how the brain heals, and it can shift.")

        case .psychoedSmallSteps:
            iconTile("figure.walk", Token.sageDeep, Token.sageCard)
            heading("Small actions change mood.",
                    "One tiny, doable step can bring back a sense of control, and that's what we'll plan together now.")

        case .breathing:
            heading("Take two slow breaths before we make the plan.", nil)
            BreathingCircle(cycles: $breathCycles)

        case .topStruggle:
            heading("What feels hardest right now?", "Pick the one that fits best.")
            SSIOptionList(options: SSIOptions.topStruggle, multi: false,
                          picks: $picks, otherText: $otherText)

        case .topHope:
            heading("What would tell you things are getting a little better?", "Pick one hope.")
            SSIOptionList(options: SSIOptions.topHope, multi: false,
                          picks: $picks, otherText: $otherText)

        case .selfTalk:
            heading("If things improved, how would you talk to yourself?", "Pick any that fit.")
            SSIOptionList(options: SSIOptions.selfTalk, multi: true,
                          picks: $picks, otherText: $otherText)

        case .betterDayPrompt:
            iconTile("sunrise.fill", Color(hex: "5f8a55"), Color(hex: "e4efdc"))
            heading("Imagine tomorrow is a little easier.",
                    "Picture \(struggleTextLowercased) feeling more manageable. Not perfect, just easier. How would you notice?")

        case .betterDayFeelings:
            heading("On that easier day, how would you feel?", "Pick any that fit.")
            SSIOptionList(options: SSIOptions.betterDayFeelings, multi: true,
                          picks: $picks, otherText: $otherText)

        case .betterDayActions:
            heading("On that easier day, what would be easier to do?", "Pick any that fit.")
            SSIOptionList(options: SSIOptions.betterDayActions, multi: true,
                          picks: $picks, otherText: $otherText)

        case .midpoint:
            iconTile("leaf.fill", Color(hex: "5f8a55"), Color(hex: "e4efdc"))
            heading("You're halfway there.",
                    "Now we'll turn that easier day into one small plan.")

        case .betterDayScale:
            heading("How close does that easier day feel right now?", nil)
            NumberDial(value: $dialValue, range: 1...10,
                       lowAnchor: "Far away", highAnchor: "Already happening")

        case .actionIntro:
            iconTile("scope", Token.primary, Token.accentTint)
            if (response.betterDayCloseness ?? 5) < 8 {
                heading("You don't need to reach 10.",
                        "Nobody starts there, and the goal is just one point closer, with one or two small doable actions.")
            } else {
                heading("That day is close.",
                        "Let's choose one or two small actions that keep you moving toward it.")
            }

        case .actionOne:
            heading("What is one small thing you could do in the next few days?", "Pick what feels doable.")
            SSIOptionList(options: SSIOptions.selfCareActions, multi: false,
                          picks: $picks, otherText: $otherText)

        case .actionTwo:
            heading("Pick one more small thing.", "A backup, or a second step.")
            SSIOptionList(options: SSIOptions.selfCareActions, multi: false,
                          picks: $picks, otherText: $otherText,
                          disabledOption: response.selfCareAction1)

        case .supportPerson:
            heading("Who could support you with this?", "A first name or role is enough: spouse, daughter, friend, PT, nurse.")
            supportField

        case .innerObstacle:
            heading("What might get in the way, from inside?", "Pick the most likely one.")
            SSIOptionList(options: SSIOptions.innerObstacle, multi: false,
                          picks: $picks, otherText: $otherText)

        case .obstacleResponse:
            heading("If \(obstacleTextLowercased) shows up, what could help?", "Pick one response.")
            SSIOptionList(options: SSIOptions.obstacleResponse, multi: false,
                          picks: $picks, otherText: $otherText)

        case .ifThenSummary:
            iconTile("arrow.triangle.branch", Token.primary, Token.accentTint)
            heading("Your if-then plan", nil)
            ifThenCard
            HStack(spacing: 12) {
                smallEdit("Change obstacle") { jump(to: .innerObstacle) }
                smallEdit("Change response") { jump(to: .obstacleResponse) }
            }

        case .almostDone:
            iconTile("sparkles", Color(hex: "5f8a55"), Color(hex: "e4efdc"))
            heading("Your plan is coming together.",
                    "Small actions add up, and after one more look it's yours.")

        case .actionPlan:
            heading("Your plan", "You can screenshot this card to keep it anywhere.")
            planCard
            shareToggle

        case .postHope1, .postHope2, .postHope3, .postHope4:
            heading("One more time: does this feel true right now?", SSIOptions.hopelessnessItems[hopeIndex(stage)])
            AgreeScale(value: $scalePick)

        case .postReadiness:
            heading("And now, how ready do you feel to take one small step?", nil)
            NumberDial(value: $dialValue, range: 0...10,
                       lowAnchor: "Not ready", highAnchor: "Very ready")

        case .completion:
            iconTile("checkmark.seal.fill", Token.sage, Token.sageCard)
            heading("You did something supportive for yourself today.",
                    completionMessage)
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch stage {
            case .landing:
                FilledCTA(title: "Start") { advance() }
            case .consent:
                FilledCTA(title: "I agree, continue") {
                    response.consentAcceptedAt = Date()
                    advance()
                }
                Button { model.goHome() } label: {
                    Text("Not now")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.muted2)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            case .safetyOffer:
                FilledCTA(title: "Continue the plan") { advance() }
            case .breathing:
                FilledCTA(title: breathCycles >= 2 ? "Continue" : "Skip for now") {
                    response.completedBreathing = breathCycles >= 2
                    advance()
                }
            case .actionPlan:
                FilledCTA(title: "Save my plan") { advance() }
            case .completion:
                FilledCTA(title: "See today's plan") {
                    model.completeSSI(response, goToPlan: true)
                }
                Button { model.completeSSI(response, goToPlan: false) } label: {
                    Text("Done for now")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.muted2)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            default:
                FilledCTA(title: "Continue") { advance() }
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.45)
            }

            if stage != .completion && stage != .safetyOffer {
                Button { model.openSafety() } label: {
                    Text("Need support right now?")
                        .font(.ui(14, .semibold))
                        .foregroundStyle(Token.muted2)
                        .underline()
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Need support right now? Opens support options.")
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
    }

    private var canAdvance: Bool {
        switch stage {
        case .preHope1, .preHope2, .preHope3, .preHope4,
             .postHope1, .postHope2, .postHope3, .postHope4:
            return scalePick != nil
        case .preReadiness, .postReadiness, .betterDayScale:
            return dialValue != nil
        case .topStruggle, .topHope, .actionOne, .actionTwo, .innerObstacle, .obstacleResponse:
            return !picks.isEmpty || !otherText.trimmingCharacters(in: .whitespaces).isEmpty
        case .selfTalk, .betterDayFeelings, .betterDayActions:
            return !picks.isEmpty || !otherText.trimmingCharacters(in: .whitespaces).isEmpty
        case .supportPerson:
            return true  // never blocks — "not sure yet" is allowed
        default:
            return true
        }
    }

    // MARK: Navigation

    // MARK: Voice

    /// Stages where speaking can answer the question.
    private var stageTakesVoice: Bool {
        switch stage {
        case .preHope1, .preHope2, .preHope3, .preHope4,
             .postHope1, .postHope2, .postHope3, .postHope4,
             .preReadiness, .postReadiness, .betterDayScale,
             .topStruggle, .topHope, .selfTalk,
             .betterDayFeelings, .betterDayActions,
             .actionOne, .actionTwo, .innerObstacle, .obstacleResponse,
             .supportPerson:
            return true
        default:
            return false
        }
    }

    private var currentOptions: [String] {
        switch stage {
        case .topStruggle:       return SSIOptions.topStruggle
        case .topHope:           return SSIOptions.topHope
        case .selfTalk:          return SSIOptions.selfTalk
        case .betterDayFeelings: return SSIOptions.betterDayFeelings
        case .betterDayActions:  return SSIOptions.betterDayActions
        case .actionOne, .actionTwo: return SSIOptions.selfCareActions
        case .innerObstacle:     return SSIOptions.innerObstacle
        case .obstacleResponse:  return SSIOptions.obstacleResponse
        default: return []
        }
    }

    private var stageIsMultiPick: Bool {
        switch stage {
        case .selfTalk, .betterDayFeelings, .betterDayActions: return true
        default: return false
        }
    }

    /// Turn a finished transcript into a selection. Voice picks; the person
    /// still confirms with Continue.
    private var voiceConfiguration: HandsFreeCaptureConfiguration {
        let captureStage = stage
        return HandsFreeCaptureConfiguration(id: "ssi.\(captureStage.rawValue)",
                                             autoStart: model.autoVoiceInput,
                                             onCommand: { command in
            guard command == .goBack, stage == captureStage else { return false }
            goBack()
            return true
        }) { transcript in
            guard stage == captureStage else { return .complete }
            return await handleVoice(transcript)
        }
    }

    private var navigationVoiceConfiguration: HandsFreeCaptureConfiguration {
        let captureStage = stage
        return HandsFreeCaptureConfiguration(
            id: "ssi.navigation.\(captureStage.rawValue)",
            hint: "Say back, repeat, help, home, or stop",
            autoStart: model.autoVoiceInput,
            continuous: true,
            onCommand: { command in
                guard command == .goBack, stage == captureStage else { return false }
                goBack()
                return true
            }
        ) { _ in
            .confirming("Try saying back, repeat, help, home, or stop.") {}
        }
    }

    private func handleVoice(_ transcript: String) async -> HandsFreeTranscriptResult {
        switch stage {
        case .preHope1, .preHope2, .preHope3, .preHope4,
             .postHope1, .postHope2, .postHope3, .postHope4:
            if let index = SSIVoiceInterpreter.agreeIndex(from: transcript) {
                scalePick = index
                voiceNote = "Picked “\(SSIOptions.hopelessnessScale[index - 1])” from what you said."
                return handsFreeResult(confirming: SSIOptions.hopelessnessScale[index - 1])
            } else {
                voiceNote = "Heard “\(transcript)”. Tap the answer that fits."
                return .complete
            }

        case .preReadiness, .postReadiness:
            return applyVoiceNumber(transcript, range: 0...10)
        case .betterDayScale:
            return applyVoiceNumber(transcript, range: 1...10)

        case .supportPerson:
            supportText = transcript
            voiceNote = nil
            return handsFreeResult(confirming: transcript)

        default:
            let options = currentOptions
            guard !options.isEmpty else { return .complete }
            let multi = stageIsMultiPick
            let taken = stage == .actionTwo ? response.selfCareAction1 : nil
            voiceNote = "Matching what you said…"
            let candidates = options.filter { $0 != taken }
            if let match = await SSIVoiceInterpreter.pickOption(transcript, options: candidates) {
                if multi { picks.insert(match) } else { picks = [match]; otherText = "" }
                voiceNote = "Picked “\(match)” from what you said."
                return handsFreeResult(confirming: match)
            } else {
                // Their own words become the custom answer. Nothing is lost.
                otherText = transcript
                if !multi { picks = [] }
                voiceNote = "Kept your words as your own answer."
                return handsFreeResult(confirming: transcript)
            }
        }
    }

    private func handsFreeResult(confirming picked: String) -> HandsFreeTranscriptResult {
        guard model.autoVoiceInput else { return .complete }
        let fromStage = stage
        return .confirming("I heard: \(picked).") {
            guard stage == fromStage, canAdvance else { return }
            advance()
        }
    }

    private func applyVoiceNumber(_ transcript: String,
                                  range: ClosedRange<Int>) -> HandsFreeTranscriptResult {
        if let n = SSIVoiceInterpreter.number(from: transcript, in: range) {
            dialValue = n
            voiceNote = "Set to \(n) from what you said."
            return handsFreeResult(confirming: "\(n)")
        } else {
            voiceNote = "Heard “\(transcript)”. Use plus and minus to pick a number."
            return .complete
        }
    }

    private func advance() {
        Haptics.light()
        handsFree.stop()
        commit(stage)
        model.autosaveSSI(response)

        let next = navigation.advance(highHopelessness: response.highHopelessness)
        prepare(next)
    }

    private func goBack() {
        handsFree.stop()
        guard let previous = navigation.goBack() else { model.goHome(); return }
        prepare(previous)
    }

    /// Jump for the if–then edit buttons; the flow re-walks forward from there.
    private func jump(to target: SSIStage) {
        handsFree.stop()
        navigation.jump(to: target)
        prepare(target)
    }

    /// Commit per-stage scratch state into the response record.
    private func commit(_ s: SSIStage) {
        let custom = otherText.trimmingCharacters(in: .whitespaces)
        func picked() -> String? { custom.isEmpty ? picks.first : custom }
        func pickedAll() -> [String] { Array(picks) + (custom.isEmpty ? [] : [custom]) }

        switch s {
        case .preHope1, .preHope2, .preHope3, .preHope4:
            response.preHopelessness[hopeIndex(s)] = scalePick
        case .postHope1, .postHope2, .postHope3, .postHope4:
            response.postHopelessness[hopeIndex(s)] = scalePick
        case .preReadiness:  response.preReadiness = dialValue
        case .postReadiness: response.postReadiness = dialValue
        case .betterDayScale: response.betterDayCloseness = dialValue
        case .topStruggle:   response.topStruggle = picked()
        case .topHope:       response.topHope = picked()
        case .selfTalk:      response.selfTalkChanges = pickedAll()
        case .betterDayFeelings: response.betterDayFeelings = pickedAll()
        case .betterDayActions:  response.betterDayActions = pickedAll()
        case .actionOne:     response.selfCareAction1 = picked()
        case .actionTwo:     response.selfCareAction2 = picked()
        case .innerObstacle: response.innerObstacle = picked()
        case .obstacleResponse: response.obstacleResponse = picked()
        case .supportPerson:
            let t = supportText.trimmingCharacters(in: .whitespaces)
            response.supportPerson = t.isEmpty ? "Not sure yet" : t
        default: break
        }
    }

    /// Load scratch state for an arriving stage so back/edit shows prior answers.
    private func prepare(_ s: SSIStage) {
        picks = []
        otherText = ""
        scalePick = nil
        dialValue = nil
        voiceNote = nil

        switch s {
        case .preHope1, .preHope2, .preHope3, .preHope4:
            scalePick = response.preHopelessness[hopeIndex(s)]
        case .postHope1, .postHope2, .postHope3, .postHope4:
            scalePick = response.postHopelessness[hopeIndex(s)]
        case .preReadiness:  dialValue = response.preReadiness
        case .postReadiness: dialValue = response.postReadiness
        case .betterDayScale: dialValue = response.betterDayCloseness
        case .topStruggle:   restore(single: response.topStruggle, from: SSIOptions.topStruggle)
        case .topHope:       restore(single: response.topHope, from: SSIOptions.topHope)
        case .selfTalk:      restore(multi: response.selfTalkChanges, from: SSIOptions.selfTalk)
        case .betterDayFeelings: restore(multi: response.betterDayFeelings, from: SSIOptions.betterDayFeelings)
        case .betterDayActions:  restore(multi: response.betterDayActions, from: SSIOptions.betterDayActions)
        case .actionOne:     restore(single: response.selfCareAction1, from: SSIOptions.selfCareActions)
        case .actionTwo:     restore(single: response.selfCareAction2, from: SSIOptions.selfCareActions)
        case .innerObstacle: restore(single: response.innerObstacle, from: SSIOptions.innerObstacle)
        case .obstacleResponse: restore(single: response.obstacleResponse, from: SSIOptions.obstacleResponse)
        case .supportPerson:
            if let s = response.supportPerson, s != "Not sure yet" { supportText = s }
        default: break
        }
    }

    private func restore(single value: String?, from options: [String]) {
        guard let value else { return }
        if options.contains(value) { picks = [value] } else { otherText = value }
    }

    private func restore(multi values: [String], from options: [String]) {
        picks = Set(values.filter { options.contains($0) })
        otherText = values.first { !options.contains($0) } ?? ""
    }

    private func restoreDraft() {
        if let draft = model.savedSSIDraft() { response = draft }
        prepare(stage)
    }

    private func hopeIndex(_ s: SSIStage) -> Int {
        switch s {
        case .preHope1, .postHope1: return 0
        case .preHope2, .postHope2: return 1
        case .preHope3, .postHope3: return 2
        default: return 3
        }
    }

    // MARK: Derived copy

    private var struggleTextLowercased: String {
        (response.topStruggle ?? "the hard part").lowercasedFirst
    }

    private var obstacleTextLowercased: String {
        (response.innerObstacle ?? "something").lowercasedFirst
    }

    private var completionMessage: String {
        var lines = ["Your next small step is ready and waiting in your activities."]
        if let lift = response.readinessLift {
            lines.insert("Your readiness moved up \(lift) point\(lift == 1 ? "" : "s") during this session.", at: 0)
        }
        if response.sharedWithCareTeam {
            lines.append("Your plan was shared with your care team.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Pieces

    private var supportField: some View {
        VStack(spacing: 12) {
            TextField("Name or role (optional)", text: $supportText)
                .font(.ui(18))
                .padding(.horizontal, 18)
                .frame(minHeight: 58)
                .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1.5))
                .submitLabel(.done)
            Button {
                supportText = ""
                advance()
            } label: {
                Text("I'm not sure yet")
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Token.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Token.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    private var ifThenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If this shows up")
                .font(.ui(14, .semibold)).foregroundStyle(Token.muted2)
            Text(response.innerObstacle ?? "—")
                .font(.display(22, .medium)).foregroundStyle(Token.heading2)
            Text("then I will")
                .font(.ui(14, .semibold)).foregroundStyle(Token.muted2)
            Text(response.obstacleResponse ?? "—")
                .font(.display(22, .medium)).foregroundStyle(Token.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Token.borderSage, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            planSection("My two small actions",
                        [response.selfCareAction1, response.selfCareAction2].compactMap { $0 })
            planSection("Support", ["I can reach out to \(response.supportPerson ?? "someone I trust")"])
            planSection("If/then plan",
                        ["If \(obstacleTextLowercased) shows up, I will \((response.obstacleResponse ?? "").lowercasedFirst)."])
            if !response.betterDayFeelings.isEmpty {
                planSection("My easier day", ["I would " + response.betterDayFeelings.prefix(3).map(\.lowercasedFirst).joined(separator: " · ")])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Token.borderOutline, lineWidth: 1.5))
    }

    @ViewBuilder private func planSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.ui(11, .bold)).kerning(1.1)
                .foregroundStyle(Token.muted2)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "5f8a55"))
                        .padding(.top, 5)
                    Text(item)
                        .font(.ui(16, .medium))
                        .foregroundStyle(Token.heading2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var shareToggle: some View {
        Button {
            Haptics.light()
            response.sharedWithCareTeam.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: response.sharedWithCareTeam ? "checkmark.square.fill" : "square")
                    .font(.system(size: 26))
                    .foregroundStyle(response.sharedWithCareTeam ? Token.primary : Token.muted3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share this plan with my care team")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.heading2)
                    Text("They see the plan, never your private ratings.")
                        .font(.ui(13))
                        .foregroundStyle(Token.muted2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(response.sharedWithCareTeam ? Token.primary : Token.borderCard, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Share this plan with my care team. \(response.sharedWithCareTeam ? "On" : "Off")")
        .accessibilityAddTraits(response.sharedWithCareTeam ? [.isSelected] : [])
    }

    private func smallEdit(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(14, .semibold))
                .foregroundStyle(Token.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Token.accentTint, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func iconTile(_ name: String, _ color: Color, _ tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(tint)
                .frame(width: 84, height: 84)
            Image(systemName: name)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func heading(_ title: String, _ sub: String?) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.display(26, .medium))
                .foregroundStyle(Token.heading2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let sub {
                Text(sub)
                    .font(.ui(16))
                    .foregroundStyle(Token.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 310)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
            Text(text)
                .font(.ui(12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Token.muted3)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Token.borderCard, lineWidth: 1))
    }

    // MARK: Narration

    private var spoken: String {
        switch stage {
        case .landing: return "Build one small plan for today. It takes about 5 minutes and you can stop any time."
        case .consent: return "Before we start: your answers stay on this phone. At the end you can choose to share your plan with your care team, or not. This is support, not emergency care."
        case .preHope1, .preHope2, .preHope3, .preHope4,
             .postHope1, .postHope2, .postHope3, .postHope4:
            return "Does this feel true right now? \(SSIOptions.hopelessnessItems[hopeIndex(stage)]) Choose strongly disagree, somewhat disagree, somewhat agree, or strongly agree."
        case .safetyOffer: return "That sounds heavy, and thank you for being honest. Would you like to see support options first? The plan will wait for you."
        case .preReadiness, .postReadiness: return "How ready do you feel to take one small step for your mental health right now? Use plus and minus, from zero, not ready, to ten, very ready."
        case .psychoedCommon: return "Recovery can feel lonely, but mood changes after a stroke are common. About 1 in 3 survivors go through this."
        case .psychoedStuck: return "Feeling stuck makes everything harder. Low mood can make rehab, meals, rest, and reaching out feel out of reach. That's the low mood talking, not you."
        case .psychoedNoFault: return "This is not a personal failure. It's part of how the brain heals, and it can shift."
        case .psychoedSmallSteps: return "Small actions change mood. One tiny doable step can bring back a sense of control, and that's what we'll plan together now."
        case .breathing: return "Take two slow breaths before we make the plan. Breathe in for four seconds, and out for four seconds."
        case .topStruggle: return "What feels hardest right now? Pick the one that fits best."
        case .topHope: return "What would tell you things are getting a little better? Pick one hope."
        case .selfTalk: return "If things improved, how would you talk to yourself? Pick any that fit."
        case .betterDayPrompt: return "Imagine tomorrow is a little easier. Picture the hard part feeling more manageable. Not perfect, just easier."
        case .betterDayFeelings: return "On that easier day, how would you feel? Pick any that fit."
        case .betterDayActions: return "On that easier day, what would be easier to do? Pick any that fit."
        case .midpoint: return "You're halfway there. Now we'll turn that easier day into one small plan."
        case .betterDayScale: return "How close does that easier day feel right now? From one, far away, to ten, already happening."
        case .actionIntro: return "The goal is not to fix everything today, just one or two small doable actions."
        case .actionOne: return "What is one small thing you could do in the next few days? Pick what feels doable."
        case .actionTwo: return "Pick one more small thing, maybe a backup or a second step."
        case .supportPerson: return "Who could support you with this? A first name or role is enough. You can also say, I'm not sure yet."
        case .innerObstacle: return "What might get in the way, from inside? Pick the most likely one."
        case .obstacleResponse: return "If that shows up, what could help? Pick one response."
        case .ifThenSummary: return "Your if then plan. If \(obstacleTextLowercased) shows up, then I will \((response.obstacleResponse ?? "").lowercasedFirst)."
        case .almostDone: return "Your plan is coming together, and small actions add up."
        case .actionPlan: return "Your plan brings together your two small actions, your support person, and your if then plan. You can share it with your care team if you want."
        case .completion: return "You did something supportive for yourself today. \(completionMessage)"
        }
    }
}

// MARK: - 4-point agree scale (one item per screen)

private struct AgreeScale: View {
    @Binding var value: Int?

    var body: some View {
        VStack(spacing: 11) {
            ForEach(Array(SSIOptions.hopelessnessScale.enumerated()), id: \.offset) { i, label in
                let score = i + 1
                let selected = value == score
                Button {
                    Haptics.light()
                    value = score
                } label: {
                    HStack {
                        Text(label)
                            .font(.ui(17, .semibold))
                            .foregroundStyle(Token.heading2)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Token.primary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selected ? Token.primary.opacity(0.10) : Token.cardSurface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selected ? Token.primary : Token.borderCard, lineWidth: 2))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - 0–10 dial with big +/- targets (no sliders — motor-friendly)

private struct NumberDial: View {
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let lowAnchor: String
    let highAnchor: String

    private var shown: Int { value ?? (range.lowerBound + range.upperBound) / 2 }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 22) {
                dialButton("minus") {
                    value = max(range.lowerBound, shown - (value == nil ? 0 : 1))
                }
                Text(value == nil ? "–" : "\(shown)")
                    .font(.display(64, .medium))
                    .foregroundStyle(value == nil ? Token.muted3 : Token.heading1)
                    .frame(minWidth: 96)
                    .contentTransition(.numericText())
                dialButton("plus") {
                    value = min(range.upperBound, shown + (value == nil ? 0 : 1))
                }
            }
            HStack {
                Text("\(range.lowerBound) · \(lowAnchor)")
                Spacer()
                Text("\(range.upperBound) · \(highAnchor)")
            }
            .font(.ui(13, .medium))
            .foregroundStyle(Token.muted2)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating from \(range.lowerBound), \(lowAnchor), to \(range.upperBound), \(highAnchor).")
        .accessibilityValue(value == nil ? "Not set" : "\(shown)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, shown + (value == nil ? 0 : 1))
            case .decrement: value = max(range.lowerBound, shown - (value == nil ? 0 : 1))
            @unknown default: break
            }
        }
    }

    private func dialButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Token.primary)
                .frame(width: 68, height: 68)
                .background(Token.accentTint, in: Circle())
                .overlay(Circle().strokeBorder(Token.borderChip, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Option list (max 5 visible, "More choices" expander, Other → short text)

private struct SSIOptionList: View {
    let options: [String]
    let multi: Bool
    @Binding var picks: Set<String>
    @Binding var otherText: String
    var disabledOption: String? = nil

    @State private var expanded = false
    @State private var showOther = false
    @FocusState private var otherFocused: Bool

    private var visible: [String] {
        // Never bury a previously made pick behind the expander.
        if expanded { return options }
        var head = Array(options.prefix(5))
        for p in picks where !head.contains(p) && options.contains(p) { head.append(p) }
        return head
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(visible, id: \.self) { option in
                optionRow(option)
            }

            if !expanded && options.count > 5 {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { expanded = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                        Text("More choices")
                            .font(.ui(15, .semibold))
                    }
                    .foregroundStyle(Token.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Token.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }

            // "Other / type my own"
            if showOther || !otherText.isEmpty {
                TextField("Type my own…", text: $otherText)
                    .font(.ui(17))
                    .focused($otherFocused)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(otherText.isEmpty ? Token.borderCard : Token.primary, lineWidth: 1.5))
                    .submitLabel(.done)
                    .onChange(of: otherText) { _, text in
                        if !multi && !text.isEmpty { picks = [] }
                    }
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showOther = true }
                    otherFocused = true
                } label: {
                    Text("Other: type my own")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Token.muted)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Token.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func optionRow(_ option: String) -> some View {
        let selected = picks.contains(option)
        let disabled = option == disabledOption
        return Button {
            guard !disabled else { return }
            Haptics.light()
            if multi {
                if selected { picks.remove(option) } else { picks.insert(option) }
            } else {
                picks = [option]
                otherText = ""
            }
        } label: {
            HStack(spacing: 12) {
                if multi {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Token.primary : Token.muted3)
                }
                Text(option)
                    .font(.ui(16.5, .semibold))
                    .foregroundStyle(disabled ? Token.muted3 : Token.heading2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if disabled {
                    Text("Picked")
                        .font(.ui(12, .bold))
                        .foregroundStyle(Token.muted3)
                } else if !multi && selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Token.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? Token.primary.opacity(0.10) : Token.cardSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Token.primary : Token.borderCard, lineWidth: 2))
            .opacity(disabled ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(option)\(disabled ? ". Already picked as your first action." : "")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Breathing (4s in / 4s out, two cycles; reduce-motion safe)

private struct BreathingCircle: View {
    @Binding var cycles: Int
    @State private var inhale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Token.accentTint)
                    .frame(width: 170, height: 170)
                    .scaleEffect(reduceMotion ? 1 : (inhale ? 1.18 : 0.82))
                Circle()
                    .strokeBorder(Token.borderOutline, lineWidth: 2)
                    .frame(width: 170, height: 170)
                    .scaleEffect(reduceMotion ? 1 : (inhale ? 1.18 : 0.82))
                Text(inhale ? "Breathe in" : "Breathe out")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Token.primary)
            }
            .frame(height: 210)
            Text(cycles >= 2 ? "Lovely, ready when you are." : "Four seconds in, four seconds out.")
                .font(.ui(14))
                .foregroundStyle(Token.muted2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Breathing guide. Breathe in for four seconds, out for four seconds. \(cycles >= 2 ? "Two breaths done." : "")")
        .task {
            while !Task.isCancelled {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 4)) { inhale = true }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 4)) { inhale = false }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                cycles += 1
            }
        }
    }
}

// MARK: - Helpers

private extension String {
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}

#Preview {
    let m = AppModel(); m.screen = .boost
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
