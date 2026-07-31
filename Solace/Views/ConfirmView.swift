import SwiftUI

struct ConfirmView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let mood = model.selectedMood ?? Mood.all[2]
        let spoken = "You said you feel \(mood.word). \(mood.confirmMessage) Tap next to pick one small thing."

        VStack(spacing: 26) {
            ScreenHeader(speak: spoken, onBack: nil)
                .padding(.horizontal, -6)

            Spacer()

            ZStack {
                Circle()
                    .fill(mood.color)
                    .frame(width: 140, height: 140)
                    .shadow(color: Color(hex: "503217").opacity(0.5), radius: 18, x: 0, y: 16)
                SolaceFace(mouth: mood.mouth, size: 78, stroke: Token.onPrimary, lineWidth: 1.5)
            }

            VStack(spacing: 6) {
                Eyebrow(text: "You said you feel", tracking: 1.6)
                Text(mood.word)
                    .font(.display(34, .medium))
                    .foregroundStyle(Token.heading2)
            }

            Text(mood.confirmMessage)
                .font(.ui(17))
                .foregroundStyle(Token.body)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: 260)

            Button { model.goActivities() } label: {
                Text("Next")
                    .font(.ui(18, .bold))
                    .foregroundStyle(Token.onPrimary)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 17)
                    .background(Token.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Token.ctaShadowBase.opacity(0.55), radius: 12, x: 0, y: 10)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 30)
        .padding(.bottom, 40)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration)
    }

    private var captureConfiguration: HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(
            id: "confirm",
            hint: "Say next to pick one small thing",
            autoStart: model.autoVoiceInput,
            continuous: true,
            earlyFinish: { Self.isNext($0) }
        ) { text in
            guard Self.isNext(text) else { return .complete }
            return .confirming("Let's pick one small thing.") {
                guard model.screen == .confirm else { return }
                model.goActivities()
            }
        }
    }

    private static func isNext(_ transcript: String) -> Bool {
        VoicePhraseMatcher.matches(transcript, anyOf: [
            "next", "continue", "okay", "ok", "go on", "pick one", "pick something", "yes"
        ])
    }
}

#Preview {
    let m = AppModel(); m.screen = .confirm; m.selectMood(3)
    return RootView().environmentObject(m).environmentObject(Narrator())
}
