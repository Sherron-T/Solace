import SwiftUI

struct DoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringFill: Double = 0

    private var spoken: String {
        "That counts. \(model.doneMessage) You have a \(model.streakCount) day streak, and \(model.winsThisWeek) things done this week."
    }

    var body: some View {
        VStack(spacing: 26) {
            ScreenHeader(speak: spoken, onBack: nil)
                .padding(.horizontal, -6)

            Spacer()

            ring

            VStack(spacing: 10) {
                Text("That counts.")
                    .font(.display(30, .medium))
                    .foregroundStyle(Token.heading2)
                Text(model.doneMessage)
                    .font(.ui(17))
                    .foregroundStyle(Token.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 270)
            }

            tallyPill

            VStack(spacing: 11) {
                OutlineCTA(title: "See your week") { model.goTrend() }
                FilledCTA(title: "Done for now") { model.goHome() }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 30)
        .padding(.bottom, 40)
        .screenEntrance()
        .autoRead(spoken)
        .onAppear {
            if reduceMotion { ringFill = model.ringProgress }
            else { withAnimation(.easeOut(duration: 0.9)) { ringFill = model.ringProgress } }
        }
    }

    private var ring: some View {
        ZStack {
            // Wordless reward: a quiet bloom of leaves behind the ring.
            LeafBurst(size: 230)
            Circle()
                .stroke(Token.borderChip, lineWidth: 11)
                .frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: ringFill)
                .stroke(Token.primary, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .frame(width: 132, height: 132)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(model.streakCount)")
                    .font(.display(44, .medium))
                    .foregroundStyle(Token.primary)
                Text("DAY STREAK")
                    .font(.ui(12))
                    .tracking(1.0)
                    .foregroundStyle(Token.muted3)
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.streakCount) day streak")
    }

    private var tallyPill: some View {
        (
            Text("\(model.winsThisWeek) things").font(.ui(15, .bold)).foregroundColor(Token.heading2)
            + Text(" done this week").font(.ui(15)).foregroundColor(Token.body)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderCard, lineWidth: 1)
        )
    }
}

/// Secondary outline CTA used on Done.
struct OutlineCTA: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(16, .semibold))
                .foregroundStyle(Token.body)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Token.borderOutline, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    let m = AppModel(); m.screen = .done; m.activity = "pt"; m.selectMood(2)
    return RootView().environmentObject(m).environmentObject(Narrator())
}
