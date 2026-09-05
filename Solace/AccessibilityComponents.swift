import SwiftUI

// MARK: - Speaker button (read this screen aloud)

struct SpeakerButton: View {
    @EnvironmentObject private var narrator: Narrator
    var text: String

    var body: some View {
        Button { narrator.toggle(text) } label: {
            Image(systemName: narrator.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(narrator.isSpeaking ? Token.primary : Token.body)
                .frame(width: 48, height: 48)
                .background(Token.backButtonBG, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(narrator.isSpeaking ? "Stop reading aloud" : "Read this screen aloud")
        .accessibilityHint("Speaks the current screen in a natural voice.")
    }
}

// MARK: - Settings gear (live accessibility toggles)

struct SettingsGearButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.showSettings = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Token.body)
                .frame(width: 48, height: 48)
                .background(Token.backButtonBG, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accessibility settings")
        .accessibilityHint("Adjust the layout, text, picture, voice, and visual support options.")
    }
}

// MARK: - Accessibility profile summary

/// A plain-language snapshot of the accommodations currently active for the
/// survivor. Keeping this visible in Settings makes the app's adaptive behavior
/// discoverable without requiring a person to remember which controls they chose.
struct AccessibilityProfileCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var activeSupports: [String] {
        var supports = ["\(model.workingHand == .right ? "Right" : "Left")-hand layout",
                        "\(model.textScale.label.lowercased()) text"]
        if model.preferPictures { supports.append("picture cues") }
        if model.autoReadAloud { supports.append("read-aloud screens") }
        if model.autoVoiceInput { supports.append("hands-free listening") }
        if model.neglectSide != .none { supports.append("visual anchor") }
        if reduceMotion { supports.append("reduced motion") }
        if differentiateWithoutColor { supports.append("non-color cues") }
        return supports
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "accessibility")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Token.primary)
                    .frame(width: 42, height: 42)
                    .background(Token.accentTint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your access profile")
                        .font(.ui(17, .semibold))
                        .foregroundStyle(Token.heading2)
                    Text("These supports are active now")
                        .font(.ui(13))
                        .foregroundStyle(Token.muted2)
                }
                Spacer(minLength: 0)
            }

            Text(activeSupports.formatted(.list(type: .and)))
                .font(.ui(15, .medium))
                .foregroundStyle(Token.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Active supports: \(activeSupports.formatted(.list(type: .and)))")
        }
        .padding(16)
        .background(Token.sageCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Token.borderSage, lineWidth: 1)
        )
    }
}

// MARK: - Handedness-aware screen header
//
// The interactive chrome (back, speaker) sits on the user's working-hand side so a
// one-handed thumb can reach it. Title text stays left-aligned for readability.

struct ScreenHeader: View {
    @EnvironmentObject private var model: AppModel
    var title: String? = nil
    var subtitle: String? = nil
    var titleSize: CGFloat = 23
    var speak: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Interactive cluster lives on the working-hand side, back outermost,
            // so a one-handed thumb reaches everything.
            if model.isRightHanded {
                titleBlock
                SpeakerButton(text: speak)
                if let onBack { BackButton(action: onBack) }
            } else {
                if let onBack { BackButton(action: onBack) }
                SpeakerButton(text: speak)
                titleBlock
            }
        }
    }

    @ViewBuilder private var titleBlock: some View {
        if title != nil || subtitle != nil {
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 1) {
                if let title {
                    Text(title)
                        .font(.display(titleSize))
                        .foregroundStyle(Token.heading3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(14))
                        .foregroundStyle(Token.muted2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Visuospatial-neglect anchoring
//
// Standard neglect rehab uses a bright "anchor" at the edge of the neglected
// field to cue scanning ("find the green line first"). We draw a high-contrast
// stripe on the neglected edge and nudge content toward the intact field so
// nothing critical starts inside the blind region.

private struct NeglectAnchorModifier: ViewModifier {
    let side: NeglectSide

    func body(content: Content) -> some View {
        content
            .padding(.leading, side == .left ? 16 : 0)
            .padding(.trailing, side == .right ? 16 : 0)
            .overlay(alignment: side == .right ? .trailing : .leading) {
                if side != .none {
                    anchorStripe
                }
            }
    }

    private var anchorStripe: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Token.primary)
            Capsule()
                .fill(Token.primary)
                .frame(width: 6)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 70)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Draws the neglected-side anchor stripe and shifts content toward the
    /// intact visual field. No-op when `side == .none`.
    func neglectAnchor(_ side: NeglectSide) -> some View {
        modifier(NeglectAnchorModifier(side: side))
    }
}

// MARK: - Auto-read on appear (when "read aloud" is enabled)

private struct AutoReadModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var narrator: Narrator
    let text: String

    func body(content: Content) -> some View {
        content
            .onAppear { if model.autoReadAloud { narrator.speak(text) } }
            // Only silence our own narration. During a tab switch the new
            // screen starts speaking before this one disappears; a blanket
            // stop() here was cutting the new screen off instantly.
            .onDisappear { narrator.stopIfSpeaking(text) }
    }
}

extension View {
    /// Speaks `text` when the screen appears, if the read-aloud preference is on.
    func autoRead(_ text: String) -> some View { modifier(AutoReadModifier(text: text)) }
}
