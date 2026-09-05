import SwiftUI

/// Live accessibility controls — every change applies immediately to the app
/// underneath, which makes for a strong on-stage "watch it adapt" moment.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDemoTools = false
    @State private var patientNameDraft = ""
    @State private var careTeamNameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Make it yours")
                        .font(.display(28, .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Token.heading2)
                        // Hidden demo hook: hold the title to restore the
                        // seeded state without reinstalling (permissions stay).
                        .onLongPressGesture(minimumDuration: 1.5) {
                            Haptics.light()
                            showDemoTools = true
                        }
                    Spacer()
                    SpeakerButton(text: spoken)
                }

                AccessibilityProfileCard()
                    .accessibilityElement(children: .contain)

                section("Working hand", "Buttons move to your reachable side") {
                    segmented(["Left", "Right"], selected: model.isRightHanded ? 1 : 0) { i in
                        model.setWorkingHand(i == 0 ? .left : .right)
                    }
                }

                section("Text size", nil) {
                    HStack(spacing: 6) {
                        ForEach(Array(TextScale.allCases.enumerated()), id: \.offset) { i, scale in
                            let selected = model.textScale == scale
                            Button { model.setTextScale(scale) } label: {
                                // Fixed glyph sizes on purpose — the previews must not scale.
                                Text("A")
                                    .font(.system(size: [16, 21, 27][i], weight: .semibold, design: .serif))
                                    .foregroundStyle(selected ? Token.onPrimary : Token.body)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(selected ? Token.primary : Token.cardSurface,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(selected ? .clear : Token.borderCard, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Text size: \(scale.label)")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }
                }

                section("A bright line on one side", "Helps your eyes find the side that gets missed") {
                    segmented(["Left", "Off", "Right"],
                              selected: model.neglectSide == .left ? 0 : (model.neglectSide == .right ? 2 : 1)) { i in
                        model.setNeglectSide(i == 0 ? .left : (i == 2 ? .right : NeglectSide.none))
                    }
                }

                section("Show feelings as faces", "Helpful when words are hard") {
                    toggle(model.preferPictures) { model.setPreferPictures($0) }
                }

                section("Read screens aloud", "Solace speaks each screen") {
                    toggle(model.autoReadAloud) { model.setAutoReadAloud($0) }
                }

                section("Listen automatically", "After each question, the mic opens for 10 seconds so you can answer out loud") {
                    toggle(model.autoVoiceInput) { model.setAutoVoiceInput($0) }
                    if model.autoVoiceInput {
                        Text("Voice commands: home, back, repeat, activities, trends, check in, settings, help, and stop.")
                            .font(.ui(12.5))
                            .foregroundStyle(Token.muted2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                section("CareBridge names", "Choose the names used in caregiver updates and support screens") {
                    VStack(spacing: 10) {
                        nameField("Your name in CareBridge", text: $patientNameDraft)
                            .onChange(of: patientNameDraft) { _, value in
                                if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                                    model.setPatientName(value)
                                }
                            }
                        nameField("Care team name", text: $careTeamNameDraft)
                            .onChange(of: careTeamNameDraft) { _, value in
                                if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                                    model.setCareTeamName(value)
                                }
                            }
                    }
                }

                section("A gentle weekly goal", "Choose a pace that feels doable. Missing a day never counts against you.") {
                    HStack(spacing: 6) {
                        ForEach([3, 6, 10], id: \.self) { goal in
                            Button {
                                model.setWeeklyGoal(goal)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(goal)")
                                        .font(.display(22, .medium))
                                    Text(goal == 1 ? "thing" : "things")
                                        .font(.ui(11, .semibold))
                                }
                                .foregroundStyle(model.weeklyGoal == goal ? Token.onPrimary : Token.body)
                                .frame(maxWidth: .infinity, minHeight: 55)
                                .background(model.weeklyGoal == goal ? Token.primary : Token.cardSurface,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(model.weeklyGoal == goal ? .clear : Token.borderCard, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Weekly goal: \(goal) \(goal == 1 ? "thing" : "things")")
                            .accessibilityValue(model.weeklyGoal == goal ? "Selected" : "Not selected")
                            .accessibilityAddTraits(model.weeklyGoal == goal ? [.isSelected] : [])
                        }
                    }
                }

                FirebaseConnectionCard()

                PrivacySharingCard()

                section("One gentle reminder a day", "Never a guilt trip, and skipped days are never mentioned.") {
                    toggle(model.reminderOn) { model.setReminder($0) }
                }

                VStack(spacing: 10) {
                    Button {
                        dismiss()
                        model.replayOnboarding()
                    } label: {
                        Text("Replay setup")
                            .font(.ui(16, .semibold))
                            .foregroundStyle(Token.body)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Token.borderOutline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle())

                    if model.didBoost {
                        Button {
                            dismiss()
                            model.openBoost()
                        } label: {
                            Text("Rebuild my small plan")
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
                .padding(.top, 4)

                FilledCTA(title: "Done") { dismiss() }
            }
            .padding(24)
        }
        .background(Token.screenBG.ignoresSafeArea())
        .onAppear {
            patientNameDraft = model.patientName
            careTeamNameDraft = model.careTeamName
        }
        .confirmationDialog("Hackathon demo tools",
                            isPresented: $showDemoTools,
                            titleVisibility: .visible) {
            Button("Load 7 fake past days in CareBridge") {
                model.loadHackathonCareBridgeHistory()
            }
            Button("Send today's reminder in 5 seconds") {
                GentleReminder.fireDemo()
                dismiss()
            }
            Button("Reset all demo data", role: .destructive) {
                dismiss()
                model.resetDemo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hidden demo-only controls that leave preferences and permissions unchanged.")
        }
    }

    // MARK: Pieces

    @ViewBuilder private func section<Content: View>(_ title: String, _ sub: String?,
                                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.ui(17, .semibold)).foregroundStyle(Token.heading2)
                if let sub { Text(sub).font(.ui(13)).foregroundStyle(Token.muted2) }
            }
            content()
        }
    }

    private func segmented(_ labels: [String], selected: Int, onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Button { onPick(i) } label: {
                    Text(label)
                        .font(.ui(15, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(i == selected ? Token.onPrimary : Token.body)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(i == selected ? Token.primary : Token.cardSurface,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(i == selected ? .clear : Token.borderCard, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(label)
                .accessibilityValue(i == selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(i == selected ? [.isSelected] : [])
            }
        }
    }

    private func toggle(_ value: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach([("Off", false), ("On", true)], id: \.0) { label, v in
                Button { onChange(v) } label: {
                    Text(label)
                        .font(.ui(15, .semibold))
                        .foregroundStyle(value == v ? Token.onPrimary : Token.body)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(value == v ? Token.sage : Token.cardSurface,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(value == v ? .clear : Token.borderCard, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(label)
                .accessibilityValue(value == v ? "Selected" : "Not selected")
                .accessibilityAddTraits(value == v ? [.isSelected] : [])
            }
        }
    }

    private func nameField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.ui(16, .semibold))
            .foregroundStyle(Token.heading2)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, 15)
            .frame(minHeight: 50)
            .background(Token.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Token.borderCard, lineWidth: 1)
            )
            .accessibilityLabel(title)
    }

    private var spoken: String {
        "Make it yours. Adjust your working hand, text size, pictures, voice controls, and CareBridge names."
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppModel())
        .environmentObject(Narrator())
}
