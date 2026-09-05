import SwiftUI

/// First-run setup that adapts the whole app to the user's body and preferences.
/// Short by design — fatigue is a core post-stroke constraint — and voice-readable.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var narrator: Narrator
    @EnvironmentObject private var handsFree: HandsFreeController

    @State private var step = 0
    @State private var hand: WorkingHand? = nil
    @State private var textScale: TextScale = .comfortable
    @State private var pictures: Bool? = nil
    @State private var readAloud: Bool? = nil
    @State private var autoVoice: Bool? = nil
    @State private var neglect: NeglectSide? = nil

    private let lastStep = 6

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ProgressDots(count: lastStep + 1, index: step)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .padding(.top, 14)
        .padding(.bottom, 32)
        .background(Token.screenBG.ignoresSafeArea())
        .id(step)            // re-run the entrance animation per step
        .transition(.opacity)
        // Voice turns on the moment "listen automatically" is chosen, so the
        // rest of setup can be answered and navigated out loud.
        .handsFreeCapture(captureConfiguration)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            if step > 0 {
                BackButton { withAnimation { step -= 1 } }
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
            Spacer()
            SpeakerButton(text: spoken)
        }
        .padding(.horizontal, 22)
    }

    // MARK: Step content

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            heading("Welcome to Solace",
                    "A calm place to check in, one small step at a time. Let’s take a moment to set it up so it fits you.")
            Image(systemName: "leaf.fill")
                .font(.system(size: 64))
                .foregroundStyle(Token.sage)
                .padding(.top, 8)
                .accessibilityHidden(true)

        case 1:
            // Speech first: if reading or listening is needed, the REST of
            // setup can already speak and listen.
            heading("Should Solace read screens aloud?",
                    "Solace can speak everything on screen. If you say yes, the rest of this setup reads itself too.")
            choice(icon: "speaker.wave.2.fill", title: "Yes, read aloud",
                   selected: readAloud == true) {
                readAloud = true
                narrator.speak("Lovely, from now on I'll read each screen to you.")
            }
            choice(icon: "speaker.slash.fill", title: "No thanks",
                   selected: readAloud == false) {
                readAloud = false
                narrator.stop()
            }

        case 2:
            heading("Should Solace listen for your answers?",
                    "After each question, the microphone can open so you can answer out loud, with no tapping needed. It closes on its own once Solace understands you.")
            choice(icon: "mic.fill", title: "Yes, listen automatically",
                   subtitle: "Answer questions by speaking",
                   selected: autoVoice == true) { autoVoice = true }
            choice(icon: "hand.tap.fill", title: "I’ll tap my answers",
                   subtitle: "The mic button is always there too",
                   selected: autoVoice == false) { autoVoice = false }

        case 3:
            heading("Which hand do you use?",
                    "We’ll put the buttons where your thumb can reach them.")
            choice(icon: "hand.point.left.fill", title: "Left hand",
                   selected: hand == .left) { hand = .left }
            choice(icon: "hand.point.right.fill", title: "Right hand",
                   selected: hand == .right) { hand = .right }

        case 4:
            heading("Do you miss things on one side?",
                    "After a stroke, one side can be easy to miss. We’ll put a bright green line on that side to help your eyes find it.")
            choice(icon: "arrow.left.to.line", title: "The left side",
                   selected: neglect == .left) { neglect = .left }
            choice(icon: "arrow.right.to.line", title: "The right side",
                   selected: neglect == .right) { neglect = .right }
            choice(icon: "checkmark.circle", title: "No, I see both sides",
                   selected: neglect == NeglectSide.none) { neglect = NeglectSide.none }

        case 5:
            heading("How big should the words be?",
                    "Pick whatever is easiest to read. Everything from here on uses your choice.")
            ForEach(TextScale.allCases) { scale in
                choice(title: scale.label,
                       previewScale: scale.multiplier,
                       selected: textScale == scale) {
                    textScale = scale
                    // Applies immediately: this screen and every one after
                    // renders at the chosen size right away.
                    AppType.scale = scale.multiplier
                }
            }

        default:
            heading("Words or pictures?",
                    "Pictures can make feelings easier to share.")
            choice(icon: "textformat", title: "Words and pictures",
                   subtitle: "A balance of both", selected: pictures == false) { pictures = false }
            choice(icon: "face.smiling", title: "More pictures",
                   subtitle: "Show feelings as faces", selected: pictures == true) { pictures = true }
            setupSummary
        }
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Solace setup")
                .font(.ui(16, .semibold))
                .foregroundStyle(Token.heading2)
            Text("\(hand == .right ? "Right" : "Left")-hand layout · \(textScale.label.lowercased()) text")
                .font(.ui(14))
                .foregroundStyle(Token.body)
            Text("\(readAloud == true ? "Read-aloud on" : "Read-aloud off") · \(autoVoice == true ? "Hands-free listening on" : "Tap-to-answer")")
                .font(.ui(14))
                .foregroundStyle(Token.body)
            Text(neglect == .none ? "No visual anchor" : "\(neglect == .left ? "Left" : "Right") visual anchor")
                .font(.ui(14))
                .foregroundStyle(Token.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderSage, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Solace setup: \(hand == .right ? "right" : "left") hand, \(textScale.label.lowercased()) text, \(readAloud == true ? "read aloud on" : "read aloud off"), \(autoVoice == true ? "hands-free listening on" : "tap to answer"), \(neglect == .none ? "no visual anchor" : "visual anchor on the \(neglect == .left ? "left" : "right")")")
    }

    // MARK: Footer CTA

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            if autoVoice == true {
                HandsFreeCapturePill(hint: "Say your answer, or say continue")
                    .padding(.bottom, 2)
            }

            FilledCTA(title: step == lastStep ? "Start" : "Continue") { advance() }
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.45)

            if step == 0 {
                Button {
                    model.completeOnboarding(hand: .right, text: .comfortable,
                                             pictures: false, readAloud: false)
                } label: {
                    Text("Skip setup")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Token.muted3)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return readAloud != nil
        case 2: return autoVoice != nil
        case 3: return hand != nil
        case 4: return neglect != nil
        case 6: return pictures != nil
        default: return true
        }
    }

    private func advance() {
        if step < lastStep {
            withAnimation { step += 1 }
            // The read-aloud choice takes effect immediately, so the rest of
            // setup already speaks (autoRead only starts after onboarding).
            if readAloud == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    narrator.speak(spoken)
                }
            }
        } else {
            model.completeOnboarding(
                hand: hand ?? .right,
                text: textScale,
                pictures: pictures ?? false,
                readAloud: readAloud ?? false,
                neglect: neglect ?? .none,
                autoVoice: autoVoice ?? false
            )
        }
    }

    private func goBackStep() {
        guard step > 0 else { return }
        withAnimation { step -= 1 }
        if readAloud == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                narrator.speak(spoken)
            }
        }
    }

    // MARK: Voice setup

    private struct VoiceChoice {
        let label: String
        let ack: String
        let apply: @MainActor () -> Void
    }

    private var captureConfiguration: HandsFreeCaptureConfiguration? {
        guard autoVoice == true else { return nil }
        let choices = voiceChoices
        let labels = choices.map(\.label)

        return HandsFreeCaptureConfiguration(
            id: "onboarding.\(step)",
            hint: "Say your answer",
            autoStart: true,
            continuous: true,
            earlyFinish: { text in
                Self.isContinue(text) ||
                SSIVoiceInterpreter.keywordMatch(text, options: labels) != nil
            },
            onCommand: { command in
                switch command {
                case .goBack:
                    goBackStep()
                case .repeatPrompt:
                    narrator.speak(spoken)
                default:
                    break   // Destinations wait until setup is done.
                }
                return true
            }
        ) { text in
            if Self.isContinue(text) {
                guard canAdvance else {
                    return .confirming("Choose an answer first, then say continue.") {}
                }
                return .confirming(step == lastStep ? "Starting Solace." : "Okay.") {
                    advance()
                }
            }

            guard let label = await SSIVoiceInterpreter.pickOption(text, options: labels),
                  let choice = choices.first(where: { $0.label == label }) else {
                return .confirming("You can say one of the answers, or say continue.") {}
            }
            choice.apply()
            return .confirming(choice.ack) {
                advance()
            }
        }
    }

    /// The spoken equivalents of each step's tappable options. Matched with
    /// the same keyword-then-Apple-Intelligence ladder the check-in screens use.
    private var voiceChoices: [VoiceChoice] {
        switch step {
        case 1:
            return [
                VoiceChoice(label: "yes, read screens aloud", ack: "Read aloud is on.") { readAloud = true },
                VoiceChoice(label: "no thanks, stay quiet", ack: "Okay, staying quiet.") { readAloud = false },
            ]
        case 2:
            return [
                VoiceChoice(label: "yes, listen automatically", ack: "Listening is on.") { autoVoice = true },
                VoiceChoice(label: "no, I will tap my answers", ack: "Okay, tapping it is.") { autoVoice = false },
            ]
        case 3:
            return [
                VoiceChoice(label: "left hand", ack: "Left hand.") { hand = .left },
                VoiceChoice(label: "right hand", ack: "Right hand.") { hand = .right },
            ]
        case 4:
            return [
                VoiceChoice(label: "the left side", ack: "The left side.") { neglect = .left },
                VoiceChoice(label: "the right side", ack: "The right side.") { neglect = .right },
                VoiceChoice(label: "no, I see both sides", ack: "Both sides, got it.") { neglect = NeglectSide.none },
            ]
        case 5:
            return TextScale.allCases.map { scale in
                VoiceChoice(label: scale.label.lowercased(), ack: "\(scale.label).") {
                    textScale = scale
                    AppType.scale = scale.multiplier
                }
            }
        case 6:
            return [
                VoiceChoice(label: "words and pictures", ack: "Words and pictures.") { pictures = false },
                VoiceChoice(label: "more pictures, with faces", ack: "More pictures.") { pictures = true },
            ]
        default:
            return []
        }
    }

    private static func isContinue(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return false }
        let padded = " \(normalized) "
        return ["continue", "next", "go on", "keep going", "start", "begin", "done", "ready"]
            .contains { padded.contains(" \($0) ") }
    }

    // MARK: Pieces

    @ViewBuilder private func heading(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.display(29, .medium))
                .foregroundStyle(Token.heading2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Text(sub)
                .font(.ui(16))
                .foregroundStyle(Token.body)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
        }
    }

    private func choice(icon: String? = nil,
                        title: String,
                        subtitle: String? = nil,
                        previewScale: CGFloat? = nil,
                        selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(selected ? Token.primary : Token.sage)
                        .frame(width: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(previewScale == nil ? .ui(18, .semibold)
                              : .system(size: 18 * previewScale!, weight: .semibold))
                        .foregroundStyle(Token.heading2)
                    if let subtitle {
                        Text(subtitle).font(.ui(13)).foregroundStyle(Token.muted2)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Token.primary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selected ? Token.primary.opacity(0.10) : Token.cardSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Token.primary : Token.borderCard, lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Narration

    private var spoken: String {
        switch step {
        case 0: return "Welcome to Solace, a calm place to check in, one small step at a time. Let’s set it up to fit you."
        case 1: return "Should Solace read screens aloud? If you say yes, the rest of this setup reads itself too. Choose yes or no thanks."
        case 2: return "Should Solace listen for your answers? After each question the microphone can open so you can answer out loud, and it closes once Solace understands you. Choose yes, listen automatically, or I'll tap my answers."
        case 3: return "Which hand do you use? We’ll put the buttons where your thumb can reach. Choose left hand or right hand."
        case 4: return "Do you miss things on one side? Choose the left side, the right side, or no, I see both sides. We’ll add a bright line to help your eyes find that side."
        case 5: return "How big should the words be? Choose comfortable, large, or largest. Your choice applies right away."
        default: return "Words or pictures? Choose words and pictures, or more pictures to show feelings as faces."
        }
    }
}

/// Small progress dots across the top of onboarding.
struct ProgressDots: View {
    var count: Int
    var index: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Token.primary : Token.borderChip)
                    .frame(width: i == index ? 18 : 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.25), value: index)
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppModel())
        .environmentObject(Narrator())
}
