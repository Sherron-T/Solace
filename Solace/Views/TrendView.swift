import SwiftUI

struct TrendView: View {
    @EnvironmentObject private var model: AppModel

    private var spoken: String {
        var s = "Your last 7 days. "
        let logged = model.weekDots.filter(\.isLogged).count
        s += "You checked in \(logged) of 7 days. "
        if model.afterCount > 0 {
            s += "Small things helped you feel better \(model.liftedCount) of \(model.afterCount) times. "
        }
        if model.trendDown {
            s += "This week’s been heavier than usual. That happens, and you don’t have to carry it alone. "
        }
        s += "\(model.careTeamName), your care team, sees these check-ins and can reach out if things dip."
        return s
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Your last 7 days",
                             titleSize: 24,
                             speak: spoken) { model.goHome() }
                    .padding(.bottom, 2)
                weekCard
                if model.afterCount > 0 { boostInsight }
                if model.trendDown { trendDownNotice }
                careTeamCard
                talkButton
            }
            .padding(.top, 14)
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
        }
        .screenEntrance()
        .autoRead(spoken)
    }

    // MARK: Behavioral-activation proof — "doing changed feeling"

    private var boostInsight: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Token.sageAvatar).frame(width: 46, height: 46)
                Image(systemName: "arrow.up.heart.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Token.sageDeep)
            }
            (
                Text("Small things helped you feel better ")
                    .font(.ui(15))
                + Text("\(model.liftedCount) of \(model.afterCount) times")
                    .font(.ui(15, .bold))
                + Text(".")
                    .font(.ui(15))
            )
            .foregroundColor(Token.sageText)
            .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderSage, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Week chart

    private var weekCard: some View {
        Card(padding: EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(model.weekDots) { dot in
                    column(dot)
                }
            }
            .frame(height: 120)
        }
    }

    private func column(_ dot: WeekDot) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Circle()
                .fill(dot.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(dot.ring, lineWidth: 2))
            Color.clear.frame(height: dot.lift)   // good days float higher
            Text(dot.label)
                .font(.ui(11, dot.isToday ? .bold : .medium))
                .foregroundStyle(Token.muted3)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dotAccessibilityLabel(dot))
    }

    private func dotAccessibilityLabel(_ dot: WeekDot) -> String {
        guard dot.isLogged else { return "\(dot.label), not logged" }
        let word = Mood.all.first { $0.color == dot.color }?.word ?? ""
        return "\(dot.label): \(word)"
    }

    // MARK: Trend-down notice

    private var trendDownNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Token.alertIcon)
                .padding(.top, 1)
            Text("This week’s been heavier than usual. That happens, and you don’t have to carry it alone.")
                .font(.ui(14))
                .foregroundStyle(Token.warmBody)
                .lineSpacing(4)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.warmAlertCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Token.borderWarm, lineWidth: 1)
        )
    }

    // MARK: Care team

    private var careTeamCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Token.sageAvatar).frame(width: 50, height: 50)
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Token.sageDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Your care team", color: Token.sage)
                (
                    Text(model.careTeamName).font(.ui(15, .bold))
                    + Text(" sees these check-ins and can reach out if things dip.").font(.ui(15))
                )
                .foregroundColor(Token.sageText)
                .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Token.borderSage, lineWidth: 1)
        )
    }

    private var talkButton: some View {
        Button { model.openSafety() } label: {
            Text("I need to talk to someone now")
                .font(.ui(14, .semibold))
                .foregroundStyle(Token.muted3)
                .underline()
                .frame(maxWidth: .infinity)
                .padding(18)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let m = AppModel(); m.screen = .trend
    return RootView().environmentObject(m).environmentObject(Narrator())
}
