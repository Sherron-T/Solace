import SwiftUI

/// Second axis of the zero-type check-in matrix: energy. Three big icon rows,
/// all in the thumb zone, skippable. No typing anywhere.
struct EnergyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var handsFree: HandsFreeController

    private let spoken = "How is your energy? Tap tired, steady, or energetic. You can also skip."

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "How is your energy?",
                         titleSize: 24,
                         speak: spoken) { model.openMood() }
                .padding(.bottom, 10)

            Spacer()

            VStack(spacing: 13) {
                ForEach(Energy.all) { level in
                    row(level)
                }
            }

            Button { model.selectEnergy(nil) } label: {
                Text("Skip")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Token.muted3)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            HandsFreeCapturePill(hint: "Say your energy")
                .padding(.top, 4)

            Spacer(minLength: 24)
        }
        .padding(.top, 14)
        .padding(.horizontal, 26)
        .padding(.bottom, 32)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration)
    }

    private var captureConfiguration: HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(id: "energy",
                                      hint: "Say your energy",
                                      autoStart: model.autoVoiceInput,
                                      earlyFinish: { SSIVoiceInterpreter.energyIndex(from: $0) != nil }) { text in
            guard let index = SSIVoiceInterpreter.energyIndex(from: text),
                  let energy = Energy.at(index) else { return .complete }
            if model.autoVoiceInput {
                return .confirming("I heard: \(energy.word).") {
                    guard model.screen == .energy else { return }
                    model.selectEnergy(index)
                }
            }
            model.selectEnergy(index)
            return .complete
        }
    }

    private func row(_ level: Energy) -> some View {
        Button { model.selectEnergy(level.index) } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Token.accentTint)
                        .frame(width: 56, height: 56)
                    Image(systemName: level.symbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Token.primary)
                }
                Text(level.word)
                    .font(.ui(19, .semibold))
                    .foregroundStyle(Token.heading2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Token.chevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1.5)
            )
            .shadow(color: Token.cardShadow.opacity(0.16), radius: 9, x: 0, y: 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Energy: \(level.word)")
    }
}

#Preview {
    let m = AppModel(); m.screen = .energy; m.selectMood(2)
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
