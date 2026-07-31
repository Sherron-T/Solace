import SwiftUI

struct ActivitiesView: View {
    @EnvironmentObject private var model: AppModel

    private var spoken: String {
        var s = "One small thing. Pick just one, that’s plenty. The choices are: "
        s += ordered.map(\.label).joined(separator: ", ") + "."
        if ordered.contains(where: \.isCarePlan) {
            s += " Care plan choices come from your care team."
        }
        if let v = model.personalValue {
            s += " Things marked for you fit what matters to you: \(v.label)."
        }
        return s
    }

    /// Value matches float up; within that, effort is matched to today's energy
    /// (tired → restful first, energetic → active first). Logic lives on the model.
    private var ordered: [Activity] { model.orderedActivities }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "One small thing",
                         subtitle: "Pick just one, that’s plenty.",
                         speak: spoken) { model.goHome() }
                .padding(.bottom, 6)
            Spacer(minLength: 8)
            list
            Spacer(minLength: 8)
        }
        .padding(.top, 14)
        .padding(.horizontal, 22)
        .padding(.bottom, 32)
        .screenEntrance()
        .autoRead(spoken)
        .handsFreeCapture(captureConfiguration)
    }

    /// Say an activity to start it — same keyword-then-Apple-Intelligence
    /// ladder as the check-in answers, run against what's on screen.
    private var captureConfiguration: HandsFreeCaptureConfiguration {
        let labels = ordered.map(\.label)
        return HandsFreeCaptureConfiguration(
            id: "activities",
            hint: "Say the one you want",
            autoStart: model.autoVoiceInput,
            continuous: true,
            earlyFinish: { SSIVoiceInterpreter.keywordMatch($0, options: labels) != nil }
        ) { text in
            let wordCount = text.split(separator: " ").count
            guard (1...8).contains(wordCount),
                  let label = await SSIVoiceInterpreter.pickOption(text, options: labels),
                  let activity = ordered.first(where: { $0.label == label }) else {
                return .complete
            }
            return .confirming("Starting: \(activity.label).") {
                guard model.screen == .activities else { return }
                model.pick(activity: activity.id)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 13) {
            ForEach(ordered) { activity in
                card(activity)
            }
        }
    }

    private func card(_ activity: Activity) -> some View {
        let forYou = model.chosenValue.map { activity.valueTags.contains($0) } ?? false
        return Button { model.pick(activity: activity.id) } label: {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(activity.tint)
                        .frame(width: 54, height: 54)
                    Image(systemName: activity.symbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(activity.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.label)
                        .font(.ui(17, .semibold))
                        .foregroundStyle(Token.heading2)
                    Text(activity.sub)
                        .font(.ui(13))
                        .foregroundStyle(Token.muted2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    if activity.isPT {
                        tag("REHAB WIN", color: Token.sage, bg: Token.sageCard)
                    }
                    if activity.isCarePlan {
                        tag("CARE PLAN", color: Token.primary, bg: Token.accentTint)
                    }
                    if activity.id.hasPrefix("ssi.") {
                        tag("MY PLAN", color: Token.sageDeep, bg: Token.sageCard)
                    } else if forYou {
                        tag("FOR YOU", color: Token.primary, bg: Token.accentTint)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(forYou ? activity.color.opacity(0.45) : Token.borderCard,
                                  lineWidth: forYou ? 1.5 : 1)
            )
            .shadow(color: Token.cardShadow.opacity(0.22), radius: 8, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(activity.label). \(activity.sub)\(activity.isPT ? " Rehab win." : "")\(activity.isCarePlan ? " From your care plan." : "")\(activity.id.hasPrefix("ssi.") ? " From your own plan." : "")\(forYou ? " Fits what matters to you." : "")")
    }

    private func tag(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(.ui(10, .bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    let m = AppModel(); m.screen = .activities
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
