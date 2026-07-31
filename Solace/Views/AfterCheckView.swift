import SwiftUI

/// Post-activity re-check — the heart of behavioral activation. Comparing how
/// you feel *after* doing something to how you felt before is what teaches the
/// brain "action changes mood." One question, three big answers, always skippable.
struct AfterCheckView: View {
    @EnvironmentObject private var model: AppModel

    private let spoken = "You did it. One quick question. How do you feel right now? A bit better, about the same, or still hard. You can also skip."

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(speak: spoken, onBack: nil)
                .padding(.horizontal, 22)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Token.sage)
                    .accessibilityHidden(true)
                Text("You did it.")
                    .font(.display(30, .medium))
                    .foregroundStyle(Token.heading2)
                Text("How do you feel right now?")
                    .font(.ui(17))
                    .foregroundStyle(Token.body)
            }
            .padding(.bottom, 30)

            VStack(spacing: 12) {
                answer("A bit better", symbol: "arrow.up.heart.fill",
                       color: Token.sage, tint: Token.sageCard, feeling: .better)
                answer("About the same", symbol: "equal.circle.fill",
                       color: Color(hex: "9a9b63"), tint: Token.moodEmpty, feeling: .same)
                answer("Still hard", symbol: "cloud.fill",
                       color: Token.alertIcon, tint: Token.warmAlertCard, feeling: .hard)
            }

            Button { model.recordAfter(nil) } label: {
                Text("Skip")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Token.muted3)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 26)
        .padding(.bottom, 32)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration)
    }

    private var captureConfiguration: HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(
            id: "after",
            hint: "Say better, the same, still hard, or skip",
            autoStart: model.autoVoiceInput,
            continuous: true,
            earlyFinish: { Self.feeling(in: $0) != nil || Self.isSkip($0) }
        ) { text in
            if Self.isSkip(text) {
                return .confirming("Okay.") {
                    guard model.screen == .after else { return }
                    model.recordAfter(nil)
                }
            }
            guard let feeling = Self.feeling(in: text) else { return .complete }
            let ack: String
            switch feeling {
            case .better: ack = "A bit better. Lovely."
            case .same: ack = "About the same. That still counts."
            case .hard: ack = "Still hard. Thank you for saying so."
            }
            return .confirming(ack) {
                guard model.screen == .after else { return }
                model.recordAfter(feeling)
            }
        }
    }

    /// Hard words are checked first so "not better" never lands on better.
    private static func feeling(in transcript: String) -> AfterFeeling? {
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "still hard", "hard", "worse", "not better", "no better", "still bad", "bad"
        ]) { return .hard }
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "a bit better", "bit better", "better", "a little better", "good"
        ]) { return .better }
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "about the same", "the same", "same", "no change"
        ]) { return .same }
        return nil
    }

    private static func isSkip(_ transcript: String) -> Bool {
        VoicePhraseMatcher.matches(transcript, anyOf: ["skip", "skip it", "no thanks", "not now"])
    }

    private func answer(_ label: String, symbol: String, color: Color,
                        tint: Color, feeling: AfterFeeling) -> some View {
        Button {
            Haptics.soft()
            model.recordAfter(feeling)
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(tint).frame(width: 46, height: 46)
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.ui(18, .semibold))
                    .foregroundStyle(Token.heading2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("I feel \(label)")
    }
}

#Preview {
    let m = AppModel(); m.screen = .after; m.activity = "outside"
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
