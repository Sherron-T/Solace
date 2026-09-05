import SwiftUI
import UIKit

// MARK: - Haptics (gentle, dignified — a nudge, never a fanfare)

enum Haptics {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Solace face (custom mouth states, smile → flat → frown)

struct SolaceFace: View {
    var mouth: MoodMouth
    var size: CGFloat
    var stroke: Color
    /// Stroke width expressed in the 24-unit design space.
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 24.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Eyes
            for eye in [CGPoint(x: 9, y: 10), CGPoint(x: 15, y: 10)] {
                let r: CGFloat = 0.7 * s
                let rect = CGRect(x: eye.x * s - r, y: eye.y * s - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(stroke))
            }

            // Mouth — quadratic curve whose center y sets the expression.
            var path = Path()
            let lineStyle = StrokeStyle(lineWidth: lineWidth * s, lineCap: .round, lineJoin: .round)
            switch mouth {
            case .flat:
                path.move(to: p(9, 14.5))
                path.addLine(to: p(15, 14.5))
            default:
                let (y0, yMid): (CGFloat, CGFloat) = {
                    switch mouth {
                    case .smile:       return (14.0, 15.7)
                    case .softSmile:   return (14.0, 15.2)
                    case .slightFrown: return (15.0, 13.6)
                    case .frown:       return (15.5, 13.4)
                    case .flat:        return (14.5, 14.5)
                    }
                }()
                let cy = (4 * yMid - y0 - y0) / 2   // control point that lands the midpoint at yMid
                path.move(to: p(8.5, y0))
                path.addQuadCurve(to: p(15.5, y0), control: p(12, cy))
            }
            ctx.stroke(path, with: .color(stroke), style: lineStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - DISCs mood circle (fill-graded bottom-to-top)

struct DiscCircle: View {
    var color: Color
    var fill: Double          // 0…1
    var diameter: CGFloat
    var ringWidth: CGFloat = 2.5

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Token.moodEmpty, location: 0),
                        .init(color: Token.moodEmpty, location: 1 - fill),
                        .init(color: color, location: 1 - fill),
                        .init(color: color, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(Circle().strokeBorder(color, lineWidth: ringWidth))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Back button (48px circular)

struct BackButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Token.body)
                .frame(width: 48, height: 48)
                .background(Token.backButtonBG, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go back")
        .accessibilityHint("Returns to the previous screen.")
    }
}

// MARK: - Primary / completion CTAs

struct FilledCTA: View {
    var title: String
    var systemImage: String? = nil
    var background: Color = Token.primary
    var foreground: Color = Token.onPrimary
    var shadow: Color = Token.ctaShadowBase.opacity(0.55)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))
                }
                Text(title).font(.ui(18, .bold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: shadow, radius: 18, x: 0, y: 12)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Subtle press feedback that respects the calm, dignified tone (no bounce).
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Card surface

struct Card<Content: View>: View {
    var background: Color = Token.cardSurface
    var border: Color = Token.borderCard
    var cornerRadius: CGFloat = 22
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                // Shadow on the backmost shape only — the translucent layers
                // above would otherwise re-shadow every child element.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
                    .shadow(color: Token.cardShadow.opacity(0.16), radius: 9, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

// MARK: - Bottom tab bar (Home · Activities · Safety)
//
// Persistent thumb-zone navigation. Items are inset from the screen edges
// (visual-neglect accommodation) and each target is ≥56pt. Safety is always
// one tap away, from anywhere.

struct SolaceTabBar: View {
    @EnvironmentObject private var model: AppModel

    private struct Item {
        let screen: Screen
        let symbol: String
        let label: String
    }

    private let items: [Item] = [
        Item(screen: .home, symbol: "house", label: "Home"),
        Item(screen: .activities, symbol: "leaf", label: "Activities"),
        Item(screen: .safety, symbol: "heart", label: "Safety"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.label) { item in
                tab(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .shadow(color: Token.cardShadow.opacity(0.18), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Token.borderCard, lineWidth: 1)
        )
        // Inset from screen margins — critical controls never hug an edge.
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
    }

    private func tab(_ item: Item) -> some View {
        let active = model.screen == item.screen
        return Button {
            switch item.screen {
            case .home: model.goHome()
            case .activities: model.goActivities()
            case .safety: model.openSafety()
            default: break
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? item.symbol + ".fill" : item.symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(item.label)
                    .font(.ui(11, .semibold))
            }
            .foregroundStyle(active ? Token.onPrimary : Token.muted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                active ? Token.primary : .clear,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - Leaf burst — the non-text reward
//
// A quiet bloom of leaves instead of confetti: immediate, wordless, dignified.

struct LeafBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomed = false
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 360
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.11))
                    .foregroundStyle(Token.sage.opacity(0.85))
                    .rotationEffect(.degrees(angle + 90))
                    .offset(y: bloomed ? -size * 0.5 : -size * 0.18)
                    .rotationEffect(.degrees(angle))
                    .opacity(bloomed ? 0 : 0.9)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: 0.9).delay(Double(i) * 0.03),
                        value: bloomed
                    )
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            bloomed = true
        }
    }
}

// MARK: - Voice "listening" equalizer

struct EqualizerBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Token.primary)
                    .frame(width: 3, height: 20)
                    .scaleEffect(y: animating ? 1.0 : 0.35, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.8)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 20)
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Screen entrance (solRise: fade + 10px rise)

private struct ScreenEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.38)) { shown = true }
            }
    }
}

extension View {
    /// solRise — every screen fades up 10px on entry, unless Reduce Motion is on.
    func screenEntrance() -> some View { modifier(ScreenEntrance()) }
}

// MARK: - Eyebrow label

struct Eyebrow: View {
    var text: String
    var color: Color = Token.muted3
    var tracking: CGFloat = 1.2

    var body: some View {
        Text(text.uppercased())
            .font(.ui(11, .semibold))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
