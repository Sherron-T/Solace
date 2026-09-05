import SwiftUI

/// Tap-along micro-rehab: five large leaf targets appear one at a time in the
/// lower two-thirds of the screen. Each tap is a low-stakes motor rep with an
/// immediate wordless reward (bloom + haptic) — implicit behavioral activation.
/// Targets are ≥96pt and inset from the edges (visual-neglect accommodation).
struct RehabGameView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var bursts: [Int] = []      // completed taps, for bloom overlays
    @State private var finished = false
    @State private var finishTask: Task<Void, Never>?

    private let total = 5
    /// Relative positions (x, y) inside the play area — kept inside 0.22…0.78
    /// horizontally so no target hugs a screen edge.
    private let spots: [(CGFloat, CGFloat)] = [
        (0.30, 0.30), (0.68, 0.42), (0.36, 0.58), (0.70, 0.74), (0.42, 0.86),
    ]

    private let spoken = "Tap each leaf as it appears, nice and easy, and five taps is the whole set."

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Tap each leaf",
                         subtitle: "Nice and easy, no rush.",
                         speak: spoken) { model.goActivities() }

            progress
                .padding(.top, 10)

            GeometryReader { geo in
                ZStack {
                    // Blooms left behind by completed taps
                    ForEach(bursts, id: \.self) { i in
                        LeafBurst(size: 130)
                            .position(x: geo.size.width * spots[i].0,
                                      y: geo.size.height * spots[i].1)
                    }

                    if step < total {
                        leafTarget
                            .position(x: geo.size.width * spots[step].0,
                                      y: geo.size.height * spots[step].1)
                    }

                    if finished {
                        VStack(spacing: 10) {
                            LeafBurst(size: 220)
                            Text("That’s the set.")
                                .font(.display(26, .medium))
                                .foregroundStyle(Token.heading2)
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.5)
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .screenEntrance()
        .autoRead(spoken)
        .onDisappear {
            finishTask?.cancel()
            finishTask = nil
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < step ? Token.sage : Token.borderChip)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step) of \(total) taps done")
    }

    private var leafTarget: some View {
        Button {
            Haptics.light()
            bursts.append(step)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { step += 1 }
            if step == total {
                finished = true
                Haptics.success()
                // A breath to enjoy the bloom, then on to the after-check.
                finishTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.4))
                    guard !Task.isCancelled else { return }
                    model.finishActivity()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Token.accentTint)
                    .frame(width: 104, height: 104)
                    .overlay(Circle().strokeBorder(Token.sage.opacity(0.5), lineWidth: 2))
                    .shadow(color: Token.cardShadow.opacity(0.25), radius: 12, x: 0, y: 8)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Token.sage)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Tap the leaf. \(step + 1) of \(total).")
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        .id(step)
    }
}

#Preview {
    let m = AppModel(); m.screen = .rehabGame; m.activity = "pt"
    return RootView()
        .environmentObject(m)
        .environmentObject(Narrator())
}
