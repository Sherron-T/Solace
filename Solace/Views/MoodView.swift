import SwiftUI

struct MoodView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var handsFree: HandsFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spoken = "How low or steady do you feel? Tap the one that fits: good, okay, low, hard, or very low. Or tap, say it instead, and speak."

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "How low or steady do you feel?",
                         titleSize: 22,
                         speak: spoken) { model.goHome() }
                .padding(.bottom, 14)
            Spacer(minLength: 8)
            moodList
            Spacer(minLength: 8)
            HandsFreeCapturePill()
                .padding(.vertical, 6)
                .padding(.bottom, 8)
            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, 22)
        .padding(.bottom, 36)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration)
    }

    private var captureConfiguration: HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(
            id: "mood",
            autoStart: model.autoVoiceInput,
            earlyFinish: { SSIVoiceInterpreter.moodIndex(from: $0) != nil },
            onPartialTranscript: { text in
                if let inferred = SSIVoiceInterpreter.moodIndex(from: text) {
                    model.selectMood(inferred)
                }
            },
            onTranscript: { text in
                let reading = await SSIVoiceInterpreter.condenseCheckin(text)
                if model.mood == nil, let mood = reading.mood {
                    model.selectMood(mood)
                }
                guard let moodIndex = model.mood,
                      let mood = Mood.at(moodIndex) else { return .complete }

                guard model.autoVoiceInput else { return .complete }
                var confirmation = "I heard: \(mood.word)"
                if let energyIndex = reading.energy, let energy = Energy.at(energyIndex) {
                    confirmation += ", and \(energy.word.lowercased())"
                }
                return .confirming(confirmation + ".") {
                    guard model.screen == .mood else { return }
                    model.voiceCheckin(mood: moodIndex, energy: reading.energy)
                }
            }
        )
    }

    // MARK: Mood list

    private var moodList: some View {
        VStack(spacing: 11) {
            ForEach(Mood.all) { mood in
                moodRow(mood)
            }
        }
    }

    private func moodRow(_ mood: Mood) -> some View {
        let selected = model.mood == mood.index
        return Button { model.selectMood(mood.index) } label: {
            HStack(spacing: 14) {
                DiscCircle(color: mood.color, fill: mood.fill, diameter: 52)
                // Picture mode: a face makes the feeling readable without words.
                if model.preferPictures {
                    SolaceFace(mouth: mood.mouth, size: 38, stroke: mood.color, lineWidth: 1.8)
                }
                Text(mood.word)
                    .font(.ui(18, .semibold))
                    .foregroundStyle(Token.heading2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(mood.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                (selected ? mood.color.opacity(0.13) : Token.cardSurface),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? mood.color : Token.borderCard, lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: selected)
        .accessibilityLabel("Feeling \(mood.word)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to choose this feeling.")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if model.mood != nil {
            FilledCTA(title: "Continue") { model.confirmMood() }
        } else {
            Text("Tap the one that fits")
                .font(.ui(15))
                .foregroundStyle(Token.muted3)
                .frame(maxWidth: .infinity)
                .padding(18)
        }
    }
}

#Preview {
    let m = AppModel(); m.screen = .mood
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
