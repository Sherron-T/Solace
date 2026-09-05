import SwiftUI

/// The caregiver's own app. Reads the patient's synthesized updates and rolled-up
/// progress live from the shared App Group container (see Shared/SharedCare.swift —
/// the seam where a Firebase/CloudKit backend would slot in). Refreshes on foreground
/// and every few seconds while visible.
struct CareDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var snapshot: CareSnapshot?
    @State private var feed: [CareUpdate] = []
    @State private var carePlanActivities: [CarePlanActivity] = []
    @State private var ssiPlan: SSIPlanSummary?
    @State private var caregiverMessages: [CaregiverMessage] = []
    @State private var responseDraft = ""
    @State private var responseSent = false
    @State private var noteText: String = ""
    @State private var draftedActivities: [CarePlanActivity] = []
    @State private var isDraftingCarePlan = false
    @State private var draftSource: String?
    @State private var draftDetail: String?
    @State private var showCurator = false

    // AI weekly synthesis (regenerated only when the underlying data changes)
    @State private var weekSummary: CareSummaryAI.Summary?
    @State private var isSummarizing = false
    @State private var summarizedFingerprint = ""

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var name: String { snapshot?.patientName ?? "Your person" }

    var body: some View {
        ZStack {
            CareToken.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    FirebaseConnectionCard()
                    statusCard
                    responseCard
                    weekCard
                    weekSummaryCard
                    if let s = snapshot, s.afterCount > 0 { liftCard(s) }
                    if let plan = ssiPlan { ssiPlanCard(plan) }
                    carePlanSection
                    curatorCard
                    feedSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }

            if isDraftingCarePlan {
                draftingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isDraftingCarePlan)
        .onAppear(perform: reload)
        .onReceive(refresh) { _ in reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        snapshot = SharedCareStore.readSnapshot()
        feed = SharedCareStore.readFeed()
        // Restyle on read so items stored before the deterministic style rules
        // existed self-heal here too, not just in the patient app.
        carePlanActivities = SharedCareStore.readCarePlanActivities().map(CarePlanStyle.restyled)
        ssiPlan = SharedCareStore.readSSIPlan()
        caregiverMessages = SharedCareStore.readCaregiverMessages()
        refreshWeekSummary()
    }

    /// Re-synthesize the plain-words week only when its inputs change, so the
    /// 2-second reload timer never spams the model.
    private func refreshWeekSummary() {
        guard let s = snapshot else { return }
        let fingerprint = "\(s.streak)|\(s.wins)|\(s.week)|\(s.liftedCount)|\(s.afterCount)|\(feed.first?.id.uuidString ?? "")"
        guard fingerprint != summarizedFingerprint, !isSummarizing else { return }
        isSummarizing = true
        Task {
            let summary = await CareSummaryAI.summarize(snapshot: s, feed: feed)
            await MainActor.run {
                weekSummary = summary
                summarizedFingerprint = fingerprint
                isSummarizing = false
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CareToken.sage)
                Text("CareBridge")
                    .font(.careSerif(28))
                    .foregroundStyle(CareToken.ink)
            }
            Text("\(name) never has to type, taps become these updates.")
                .font(.system(size: 13))
                .foregroundStyle(CareToken.muted)
        }
    }

    // MARK: Patient status

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(CareToken.sageAvatar).frame(width: 48, height: 48)
                        Text(String(name.prefix(1)))
                            .font(.careSerif(22))
                            .foregroundStyle(CareToken.sageDeep)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CareToken.heading)
                        Text(lastSeen)
                            .font(.system(size: 12))
                            .foregroundStyle(CareToken.muted)
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text("\(snapshot?.streak ?? 0)")
                            .font(.careSerif(22))
                            .foregroundStyle(CareToken.primary)
                        Text("DAY STREAK")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(CareToken.muted2)
                    }
                }

                if let s = snapshot {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("This week")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CareToken.body)
                            Spacer()
                            Text("\(s.wins) of \(s.weeklyGoal) activities")
                                .font(.system(size: 13))
                                .foregroundStyle(CareToken.muted)
                        }
                        ProgressView(value: Double(min(s.wins, s.weeklyGoal)), total: Double(s.weeklyGoal))
                            .tint(CareToken.sage)
                    }
                }

                ShareLink(item: digest) {
                    HStack(spacing: 9) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Send update to family")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(CareToken.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(CareToken.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                ShareLink(
                    item: ClinicianReportFile(snapshot: snapshot, feed: feed,
                                              ssiPlan: ssiPlan, activities: carePlanActivities),
                    preview: SharePreview("Solace Care Summary for \(name)",
                                          image: Image(systemName: "doc.text.fill"))
                ) {
                    HStack(spacing: 9) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Export clinician summary (PDF)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(CareToken.primary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(CareToken.border, lineWidth: 1.2)
                    )
                }
            }
        }
    }

    private var lastSeen: String {
        guard let first = feed.first else { return "No updates yet" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Last update " + f.localizedString(for: first.date, relativeTo: Date())
    }

    // MARK: Two-way care messages

    private let responseOptions: [(String, String)] = [
        ("I’m thinking of you", "encouragement"),
        ("How can I help today?", "checkin"),
        ("You’re doing enough for today", "encouragement")
    ]

    private var responseCard: some View {
        card(background: CareToken.sageCard) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CareToken.sageDeep)
                    Text("SEND A NOTE TO " + name.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(CareToken.muted2)
                }
                Text("A short message appears in Solace and stays available if either device goes offline.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CareToken.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(responseOptions, id: \.0) { option, kind in
                    Button {
                        sendCaregiverMessage(option, kind: kind)
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(CareToken.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 42)
                        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(CareToken.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send: \(option)")
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Write a short note", text: $responseDraft, axis: .vertical)
                        .font(.system(size: 14))
                        .lineLimit(2...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(CareToken.border, lineWidth: 1)
                        )
                    Button {
                        sendCaregiverMessage(responseDraft, kind: "encouragement")
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CareToken.onPrimary)
                            .frame(width: 44, height: 44)
                            .background(CareToken.primary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(responseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send written note")
                }

                if responseSent {
                    Label("Note saved for delivery", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CareToken.sageDeep)
                        .transition(.opacity)
                }

                if !caregiverMessages.isEmpty {
                    Divider().overlay(CareToken.border)
                    Text("RECENT NOTES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(CareToken.muted2)
                    ForEach(caregiverMessages.prefix(3)) { message in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CareToken.sage)
                            Text(message.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(CareToken.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text(message.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(CareToken.muted2)
                        }
                    }
                }
            }
        }
    }

    private func sendCaregiverMessage(_ text: String, kind: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        caregiverMessages.insert(CaregiverMessage(text: trimmed, kind: kind), at: 0)
        caregiverMessages = Array(caregiverMessages.prefix(20))
        SharedCareStore.writeCaregiverMessages(caregiverMessages)
        responseDraft = ""
        withAnimation(.easeOut(duration: 0.2)) { responseSent = true }
        Task { await FirebaseSync.shared.publishCurrentState() }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { responseSent = false } }
        }
    }

    private var digest: String {
        // The AI-synthesized family message when available, raw bullets otherwise.
        if let message = weekSummary?.familyMessage, !message.isEmpty {
            return message + "\n\n(Sent from Solace)"
        }
        let recent = feed.prefix(3).reversed().map { "• " + $0.text }
        let body = recent.isEmpty ? "No check-ins yet today." : recent.joined(separator: "\n")
        return "Update on \(name) from Solace:\n\(body)"
    }

    /// "Week in plain words" — the AI synthesis of the structured week.
    @ViewBuilder private var weekSummaryCard: some View {
        if let summary = weekSummary {
            card(background: CareToken.sageCard) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CareToken.sageDeep)
                        Text("THE WEEK IN PLAIN WORDS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(CareToken.muted2)
                    }
                    Text(summary.dashboard)
                        .font(.system(size: 14.5))
                        .foregroundStyle(CareToken.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.source == "Apple Intelligence"
                         ? "Synthesized on device from check-ins only. \"Send update to family\" uses a warmer version of this."
                         : "Composed from check-ins. \"Send update to family\" uses a warmer version of this.")
                        .font(.system(size: 11))
                        .foregroundStyle(CareToken.muted)
                }
            }
        } else if isSummarizing {
            card {
                HStack(spacing: 10) {
                    ProgressView().tint(CareToken.sage)
                    Text("Reading the week…")
                        .font(.system(size: 13))
                        .foregroundStyle(CareToken.muted)
                }
            }
        }
    }

    // MARK: Week chart (mirrors the patient's trend view)

    private var weekCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("MOOD · LAST 7 DAYS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(CareToken.muted2)
                HStack(alignment: .bottom, spacing: 6) {
                    let week = snapshot?.week ?? Array(repeating: -1, count: 7)
                    let labels = ["M", "T", "W", "T", "F", "S", "Today"]
                    ForEach(Array(week.enumerated()), id: \.offset) { i, lvl in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            let mood = lvl >= 0 ? CareMood.at(lvl) : nil
                            Circle()
                                .fill(mood?.color ?? CareToken.borderChip)
                                .frame(width: 24, height: 24)
                            Color.clear.frame(height: mood.map { CGFloat((1 - $0.fill) * 60) } ?? 0)
                            Text(labels[i])
                                .font(.system(size: 10, weight: i == 6 ? .bold : .medium))
                                .foregroundStyle(CareToken.muted2)
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 104)
            }
        }
    }

    private func liftCard(_ s: CareSnapshot) -> some View {
        card(background: CareToken.sageCard) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.heart.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CareToken.sageDeep)
                Text("Small things helped \(name) feel better \(s.liftedCount) of \(s.afterCount) times.")
                    .font(.system(size: 14))
                    .foregroundStyle(CareToken.body)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Drafting overlay (shown while Apple Intelligence reads the note)

    private var draftingOverlay: some View {
        ZStack {
            Color.black.opacity(0.10).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(CareToken.primary)
                Text("Drafting small steps")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareToken.heading)
                Text("Apple Intelligence is reading the note on this device, and nothing leaves the phone.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CareToken.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(28)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(CareToken.border, lineWidth: 1)
            )
            .shadow(color: CareToken.shadow.opacity(0.35), radius: 26, x: 0, y: 12)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drafting small steps. Apple Intelligence is reading the note on this device.")
    }

    // MARK: Patient's self-guided plan (shared with consent from the Solace SSI)

    private func ssiPlanCard(_ plan: SSIPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PATIENT'S OWN PLAN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(CareToken.muted2)

            card(background: CareToken.sageCard) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(CareToken.sageDeep)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(name) built a plan, self-guided")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CareToken.heading)
                            Text("From the in-app single-session exercise, shared with consent. \(plan.completedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 12))
                                .foregroundStyle(CareToken.muted)
                        }
                    }

                    ssiRow("Working on", plan.topStruggle)
                    ssiRow("Hoping to", plan.topHope)
                    ForEach(Array(plan.actions.enumerated()), id: \.offset) { i, action in
                        ssiRow("Action \(i + 1)", action)
                    }
                    ssiRow("Support person", plan.supportPerson)
                    ssiRow("If/then plan", "If \(plan.innerObstacle.lowercased()) shows up → \(plan.obstacleResponse.lowercased())")

                    if plan.preReadiness >= 0 && plan.postReadiness > plan.preReadiness {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                            Text("Readiness moved \(plan.preReadiness) → \(plan.postReadiness) during the session")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(CareToken.sageDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.55), in: Capsule())
                    }
                }
            }
        }
    }

    private func ssiRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(CareToken.muted2)
                .frame(width: 84, alignment: .leading)
                .padding(.top, 2)
            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(CareToken.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Care-plan activity builder

    private var carePlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CARE PLAN BUILDER")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(CareToken.muted2)

            card {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(CareToken.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Turn notes into small steps")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CareToken.heading)
                            Text("Paste care-team or PT instructions and review the draft before it appears in Solace.")
                                .font(.system(size: 13))
                                .foregroundStyle(CareToken.muted)
                                .lineSpacing(2)
                        }
                    }

                    TextEditor(text: $noteText)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 112)
                        .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(CareToken.border, lineWidth: 1)
                        )

                    Button {
                        draftCarePlan()
                    } label: {
                        HStack(spacing: 8) {
                            if isDraftingCarePlan {
                                ProgressView()
                                    .tint(CareToken.onPrimary)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(isDraftingCarePlan ? "Drafting..." : "Draft patient steps")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(CareToken.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(draftButtonDisabled ? CareToken.muted2 : CareToken.primary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(draftButtonDisabled)

                    if let draftSource, let draftDetail {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: draftSource == "Apple Intelligence" ? "sparkles" : "gearshape")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CareToken.sage)
                                .padding(.top, 1)
                            Text("\(draftSource): \(draftDetail)")
                                .font(.system(size: 12))
                                .foregroundStyle(CareToken.muted)
                                .lineSpacing(2)
                        }
                    }


                    if !draftedActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Draft for review")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CareToken.body)
                            ForEach(draftedActivities) { activity in
                                carePlanRow(activity, isDraft: true)
                            }
                            Button {
                                let approved = Array(draftedActivities.prefix(5))
                                SharedCareStore.writeCarePlanActivities(approved)
                                carePlanActivities = approved
                                Task { await FirebaseSync.shared.publishCurrentState() }
                                draftedActivities = []
                                noteText = ""
                                draftSource = nil
                                draftDetail = nil
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Approve for Solace")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundStyle(CareToken.onPrimary)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(CareToken.sage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !carePlanActivities.isEmpty {
                card(background: CareToken.sageCard) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Active in patient app")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CareToken.body)
                            Spacer()
                            Button {
                                SharedCareStore.writeCarePlanActivities([])
                                carePlanActivities = []
                                Task { await FirebaseSync.shared.publishCurrentState() }
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CareToken.muted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.48), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(carePlanActivities) { activity in
                            carePlanRow(activity, isDraft: false)
                        }
                    }
                }
            }
        }
    }

    private var draftButtonDisabled: Bool {
        isDraftingCarePlan || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Curate the patient's daily five

    private var curatorCard: some View {
        Button { showCurator = true } label: {
            card {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CareToken.accentTint)
                            .frame(width: 42, height: 42)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CareToken.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Customize the daily five")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CareToken.heading)
                        Text(SharedCareStore.readCuratedActivities().isEmpty
                             ? "Hand-pick and order what \(name) sees, from drafted steps, presets, and their own plan."
                             : "A hand-arranged list is active, tap to change it.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(CareToken.muted)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CareToken.muted2)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCurator) {
            ActivityCuratorView(carePlanActivities: carePlanActivities,
                                ssiPlan: ssiPlan) {
                reload()
            }
        }
        .accessibilityLabel("Customize the daily five activities \(name) sees in Solace.")
    }

    private func draftCarePlan() {
        let note = noteText
        isDraftingCarePlan = true
        draftSource = nil
        draftDetail = nil
        draftedActivities = []

        Task {
            let result = await CarePlanDrafting.draft(from: note)
            await MainActor.run {
                draftedActivities = result.activities
                draftSource = result.source
                draftDetail = result.detail
                isDraftingCarePlan = false
            }
        }
    }

    private func carePlanRow(_ activity: CarePlanActivity, isDraft: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(careHex: activity.tintHex))
                    .frame(width: 38, height: 38)
                Image(systemName: activity.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(careHex: activity.colorHex))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CareToken.heading)
                    if activity.isPT {
                        Text("PT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CareToken.sageDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(CareToken.accentTint, in: Capsule())
                    }
                }
                Text(activity.instruction)
                    .font(.system(size: 12))
                    .foregroundStyle(CareToken.body)
                    .lineSpacing(2)
                if isDraft {
                    Text("Source: \(activity.sourceNote)")
                        .font(.system(size: 11))
                        .foregroundStyle(CareToken.muted2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.white.opacity(isDraft ? 0.50 : 0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CareToken.border, lineWidth: 1)
        )
    }

    // MARK: Feed

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTOMATIC UPDATES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(CareToken.muted2)
            if feed.isEmpty {
                Text("Updates will appear here as \(name) uses Solace.")
                    .font(.system(size: 14))
                    .foregroundStyle(CareToken.muted)
                    .padding(.vertical, 8)
            }
            ForEach(feed) { update in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(CareToken.accentTint).frame(width: 34, height: 34)
                        Image(systemName: icon(for: update.kind))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(CareToken.sage)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.text)
                            .font(.system(size: 14))
                            .foregroundStyle(CareToken.body)
                        Text(relative(update.date))
                            .font(.system(size: 11))
                            .foregroundStyle(CareToken.muted2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CareToken.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CareToken.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(background: Color = CareToken.card,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(CareToken.border, lineWidth: 1)
            )
            .shadow(color: CareToken.shadow.opacity(0.14), radius: 9, x: 0, y: 6)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "checkin": return "face.smiling"
        case "rehab":   return "figure.strengthtraining.traditional"
        default:        return "checkmark.circle"
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    CareDashboardView()
}
