import SwiftUI

struct SafetyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    private var spoken: String {
        "It sounds really hard right now. You don’t have to get through this on your own. Reach a real person, right now. The big button calls the 988 crisis line. Below it, you can message \(model.careTeamName), your care team. Or tap I’m okay to go back."
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

                Button {
                    // Production: open a thread with the care team.
                    // Placeholder mirrors the prototype's no-op.
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .regular))
                        Text("Message \(model.careTeamName), my care team")
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
}

#Preview {
    let m = AppModel(); m.screen = .safety
    return RootView().environmentObject(m).environmentObject(Narrator())
}
