import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var spoken: String {
        var s = "\(model.greeting). \(model.dateStr). You have a \(model.streakCount) day streak. How are you feeling today? Tap the big check in button in the middle of the screen."
        if let a = model.activity(with: model.plannedActivity) {
            s += " You saved a plan for today: \(a.label)."
        }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chromeRow
            // Everything below the chrome scrolls, so extra cards (trend
            // notice, saved plan, …) never squeeze the hero off screen.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    center
                        .padding(.top, 26)
                    bottomCards
                        .padding(.top, 30)
                }
                .padding(.bottom, 12)
            }
        }
        // README padding 64/24/40; the top status-bar region is covered by the safe area.
        .padding(.top, 18)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .screenEntrance()
        .autoRead(spoken)
    }

    // MARK: Header

    /// Mirrors with the working hand: the tappable streak chip sits on the
    /// thumb side, the greeting on the other.
    private var header: some View {
        HStack(alignment: .top) {
            if model.isRightHanded {
                greetingBlock(alignment: .leading)
                Spacer()
                streakChip
            } else {
                streakChip
                Spacer()
                greetingBlock(alignment: .trailing)
            }
        }
    }

    private func greetingBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(model.greeting)
                .font(.display(30, .medium))
                .tracking(-0.3)
                .foregroundStyle(Token.heading1)
            Text(model.dateStr)
                .font(.ui(15))
                .foregroundStyle(Token.muted)
        }
    }

    /// Settings + read-aloud, parked on the working-hand side for thumb reach.
    private var chromeRow: some View {
        HStack(spacing: 8) {
            if model.isRightHanded { Spacer(minLength: 0) }
            SpeakerButton(text: spoken)
            SettingsGearButton()
            if !model.isRightHanded { Spacer(minLength: 0) }
        }
        .padding(.top, 12)
    }

    private var streakChip: some View {
        Button { model.goTrend() } label: {
            VStack(spacing: 3) {
                Text("\(model.streakCount)")
                    .font(.display(22, .medium))
                    .foregroundStyle(Token.primary)
                Text("DAYS")
                    .font(.ui(10))
                    .tracking(0.6)
                    .foregroundStyle(Token.muted3)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Token.borderChip, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(model.streakCount) day streak. See your week.")
    }

    // MARK: Center

    private var center: some View {
        VStack(spacing: 22) {
            Text("How are you feeling today?")
                .font(.display(27))
                .foregroundStyle(Token.heading3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 260)

            heroButton

            Text("Takes about a minute")
                .font(.ui(14))
                .foregroundStyle(Token.muted2)
        }
    }

    private var heroButton: some View {
        Button { model.openMood() } label: {
            VStack(spacing: 10) {
                SolaceFace(mouth: .smile, size: 56, stroke: Token.onPrimary, lineWidth: 1.6)
                Text("Check in")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Token.onPrimary)
            }
            .frame(width: 184, height: 184)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: [Token.heroLight, Token.primary],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 0, endRadius: 130
                    )
                )
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.30), lineWidth: 3).blur(radius: 2).mask(Circle())
            )
            .shadow(color: Token.ctaShadowBase.opacity(0.55), radius: 20, x: 0, y: 18)
            .scaleEffect(breathe && !reduceMotion ? 1.045 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Check in. Tell us how you feel. Takes about a minute.")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.75).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    // MARK: Bottom cards

    @ViewBuilder private var bottomCards: some View {
        VStack(spacing: 10) {
            if model.trendDown {
                trendSupportCard
            }
            if let planned = model.activity(with: model.plannedActivity) {
                plannedCard(planned)
            }
            boostCard
            activitiesCard
        }
    }

    /// Gentle early-warning: the app noticed a heavy week and quietly opens
    /// the door to support. Never an alarm, never a demand.
    private var trendSupportCard: some View {
        Button { model.openSafety() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Token.warmAlertCard)
                        .frame(width: 46, height: 46)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Token.alertIcon)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "We noticed")
                    Text("This week looks heavy")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.heading2)
                    Text("Support is here if you want it, no pressure.")
                        .font(.ui(12))
                        .foregroundStyle(Token.muted2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Token.chevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            // Flat glass cards: stacked 10pt apart, a drop shadow lands in the
            // gaps and reads as smudges, so the borders do the separating.
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Token.borderWarm, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("We noticed this week looks heavy. Support is here if you want it. Opens support options.")
    }

    /// Saved-for-later plan — resumable in one tap, no guilt attached.
    private func plannedCard(_ activity: Activity) -> some View {
        Button { model.startPlanned() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(activity.tint)
                        .frame(width: 46, height: 46)
                    Image(systemName: activity.symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(activity.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Saved for today")
                    Text(activity.label)
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.heading2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Token.chevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(activity.color.opacity(0.45), lineWidth: 1.5)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Saved for today: \(activity.label). Tap to start.")
    }

    /// One-time short lesson (single-session intervention) invitation.
    private var boostCard: some View {
        Button { model.openBoost() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Token.accentTint)
                        .frame(width: 46, height: 46)
                    Image(systemName: "map.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Token.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: model.didBoost ? "Your small plan" : "One small plan")
                    Text(model.didBoost ? "Review your small plan" : "Build your plan for today")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.heading2)
                    Text("About 5 minutes, stop any time")
                        .font(.ui(12))
                        .foregroundStyle(Token.muted2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Token.chevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(model.didBoost
                            ? "Your small plan. Review your small plan."
                            : "One small plan. Build your plan for today. About five minutes. You can stop any time.")
    }

    private var activitiesCard: some View {
        Button { model.goActivities() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Token.iconTileSage)
                        .frame(width: 46, height: 46)
                    Image(systemName: "sun.max")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Token.sage)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "One small thing")
                    Text("Pick something to do today")
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Token.heading2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Token.chevron)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("One small thing. Pick something to do today.")
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel())
        .environmentObject(Narrator())
}
