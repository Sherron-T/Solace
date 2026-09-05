import SwiftUI

struct SafetyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    private var spoken: String {
        "It sounds really hard right now. You don’t have to get through this on your own. If you have sudden new stroke symptoms, call 911 now. The next button calls the 988 crisis line. Below it, you can share a support request with \(model.careTeamName), your care team. Or tap I’m okay to go back."
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(speak: spoken, onBack: nil)
                .padding(.horizontal, -2)

            Spacer()

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Token.safetyIconBG).frame(width: 64, height: 64)
                    Image(systemName: "heart")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Token.urgent)
                }
                .padding(.bottom, 18)

                Text("It sounds really hard right now.")
                    .font(.display(28, .medium))
                    .foregroundStyle(Token.heading2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("You don’t have to get through this on your own. Reach a real person, right now.")
                    .font(.ui(17))
                    .foregroundStyle(Token.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: 280)
                    .padding(.top, 12)
            }
            .padding(.bottom, 30)

            emergencyCard

            VStack(spacing: 13) {
                FilledCTA(
                    title: "Call the 988 crisis line",
                    systemImage: "phone.fill",
                    background: Token.urgent,
                    foreground: Token.onPrimary,
                    shadow: Token.ctaShadowBase.opacity(0.6)
                ) {
                    if let url = URL(string: "tel:988") { openURL(url) }
                }
                .accessibilityHint("Calls the 988 Suicide and Crisis Lifeline")

                ShareLink(item: supportMessage) {
                    HStack(spacing: 11) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20, weight: .regular))
                        Text("Share a support request")
                            .font(.ui(17, .bold))
                    }
                    .foregroundStyle(Token.sageText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Token.borderSage, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Share a support request with \(model.careTeamName), my care team")
                .accessibilityHint("Opens the share sheet with a ready-to-send message.")

                Button { model.goHome() } label: {
                    Text("I’m okay, go back")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.muted)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 26)
        .padding(.bottom, 40)
        .screenEntrance()
        .autoRead(spoken)
    }

    private var supportMessage: String {
        "Hi \(model.careTeamName), I’m having a really hard moment and would like some support. Please check in with me when you can."
    }

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.urgent)
                Text("New stroke symptoms?")
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Token.heading2)
            }
            Text("Sudden face drooping, arm weakness, speech trouble, or a severe new headache needs emergency help.")
                .font(.ui(13.5))
                .foregroundStyle(Token.warmBody)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "tel:911") { openURL(url) }
            } label: {
                Label("Call 911", systemImage: "phone.fill")
                    .font(.ui(15, .bold))
                    .foregroundStyle(Token.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Token.urgent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Calls emergency services. Do not wait for the app if you think you may be having a stroke.")
        }
        .padding(16)
        .background(Token.warmAlertCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderWarm, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    let m = AppModel(); m.screen = .safety
    return RootView().environmentObject(m).environmentObject(Narrator())
}
