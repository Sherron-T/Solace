import SwiftUI

struct DoingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let activity = model.selectedActivity ?? model.availableActivities[0]
        let spoken = "\(activity.title). \(activity.instruction) When you’re done, tap the big I did it button at the bottom. No rush, it’ll be here later."

        VStack(spacing: 0) {
            ScreenHeader(speak: spoken) { model.goActivities() }

            Spacer()

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(activity.tint)
                        .frame(width: 96, height: 96)
                    Image(systemName: activity.symbol)
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(activity.color)
                }

                VStack(spacing: 10) {
                    Text(activity.title)
                        .font(.display(30, .medium))
                        .foregroundStyle(Token.heading2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 260)
                    Text(activity.instruction)
                        .font(.ui(16))
                        .foregroundStyle(Token.body)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 250)
                }

                if activity.isCarePlan {
                    // Provenance builds trust: this step came from a human who
                    // knows them, not from the app.
                    HStack(spacing: 7) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 12, weight: .semibold))
                        Text("From your care team")
                            .font(.ui(13, .semibold))
                    }
                    .foregroundStyle(Token.sageDeep)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Token.sageCard, in: Capsule())
                } else if model.activityMatchesValue, let v = model.personalValue {
                    HStack(spacing: 7) {
                        Image(systemName: v.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text("One small thing for \(v.phrase)")
                            .font(.ui(13, .semibold))
                    }
                    .foregroundStyle(Token.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Token.accentTint, in: Capsule())
                }
            }

            Spacer()

            if activity.usesRehabGame {
                // Physio runs as the tap-along micro-rehab game.
                FilledCTA(
                    title: "Start tapping along",
                    systemImage: "leaf.fill",
                    background: Token.sage,
                    foreground: Token.onSage,
                    shadow: Token.sageShadow.opacity(0.6)
                ) { model.startRehabGame() }
            } else {
                FilledCTA(
                    title: "I did it",
                    systemImage: "checkmark",
                    background: Token.sage,
                    foreground: Token.onSage,
                    shadow: Token.sageShadow.opacity(0.6)
                ) { model.finishActivity() }
            }

            if model.plannedActivity != activity.id {
                Button { model.planForLater() } label: {
                    Text("Save it for later today")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Token.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityHint("Puts this on your home screen to do later. Nothing is lost.")
            }

            Text("No rush, it’ll be here later")
                .font(.ui(14))
                .foregroundStyle(Token.muted3)
                .padding(.top, 4)
        }
        .padding(.top, 14)
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration(for: activity))
    }

    /// The mic stays open while the activity happens, but only short, explicit
    /// phrases act — a phone-call activity means real conversation is audible,
    /// so nothing here guesses and unmatched speech stays silent.
    private func captureConfiguration(for activity: Activity) -> HandsFreeCaptureConfiguration {
        HandsFreeCaptureConfiguration(
            id: "doing.\(activity.id)",
            hint: "Say I did it when you're done",
            autoStart: model.autoVoiceInput,
            continuous: true,
            earlyFinish: { Self.action(in: $0) != nil }
        ) { text in
            switch Self.action(in: text) {
            case .didIt:
                return .confirming("Well done.") {
                    guard model.screen == .doing else { return }
                    model.finishActivity()
                }
            case .later:
                guard model.plannedActivity != activity.id else { return .complete }
                return .confirming("Saved for later today.") {
                    guard model.screen == .doing else { return }
                    model.planForLater()
                }
            case .start:
                guard activity.usesRehabGame else { return .complete }
                return .confirming("Starting.") {
                    guard model.screen == .doing else { return }
                    model.startRehabGame()
                }
            case nil:
                return .complete
            }
        }
    }

    private enum SpokenAction { case didIt, later, start }

    private static func action(in transcript: String) -> SpokenAction? {
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "i did it", "did it", "all done", "i m done", "im done", "done", "i finished", "finished"
        ]) { return .didIt }
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "save it for later", "for later", "later", "not now", "save it"
        ]) { return .later }
        if VoicePhraseMatcher.matches(transcript, anyOf: [
            "start tapping", "start", "begin", "ready"
        ]) { return .start }
        return nil
    }
}

#Preview {
    let m = AppModel(); m.screen = .doing; m.activity = "pt"
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
