import SwiftUI

/// Compose the patient's daily five by hand: drag to reorder the active set,
/// tap to add from a library of AI-drafted care-plan steps, the app's presets,
/// and the patient's own shared plan actions. Saving syncs through the App
/// Group; the patient app then shows exactly these, in exactly this order.
/// "Use automatic order" hands control back to the app's value + energy sort.
struct ActivityCuratorView: View {
    @Environment(\.dismiss) private var dismiss

    /// Approved care-plan items currently active in the patient app.
    let carePlanActivities: [CarePlanActivity]
    /// The patient's own plan actions (only present when shared with consent).
    let ssiPlan: SSIPlanSummary?
    var onSaved: () -> Void = {}

    @State private var selected: [CarePlanActivity] = []

    private var pool: [CarePlanActivity] {
        var items = carePlanActivities
        if let ssiPlan {
            items += ssiPlan.actions.enumerated().map { index, action in
                let style = CarePlanStyle.style(for: action)
                return CarePlanActivity(id: "ssi.\(index)", label: action,
                                        sub: "From \(patientPossessive) own plan", title: action,
                                        instruction: "The smallest safe version counts.",
                                        symbol: style.symbol, colorHex: style.colorHex,
                                        tintHex: style.tintHex, isPT: false,
                                        valueTags: [], effort: 1, sourceNote: "Patient plan")
            }
        }
        items += PresetCareActivities.all
        return items
    }

    private var library: [CarePlanActivity] {
        pool.filter { item in !selected.contains { $0.id == item.id } }
    }

    private var patientPossessive: String { "the patient's" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if selected.isEmpty {
                        Text("Nothing chosen yet, so the patient app keeps its automatic order until you pick activities here.")
                            .font(.system(size: 13))
                            .foregroundStyle(CareToken.muted)
                            .listRowBackground(CareToken.card)
                    }
                    ForEach(selected) { item in
                        row(item, showsOrigin: true) {
                            Button {
                                withAnimation { selected.removeAll { $0.id == item.id } }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(CareToken.muted2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(item.label)")
                        }
                        .listRowBackground(CareToken.card)
                    }
                    .onMove { from, to in
                        selected.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Patient's daily five (drag to reorder)")
                } footer: {
                    Text("\(selected.count) of 5 chosen, and this exact order shows in Solace.")
                }

                Section {
                    ForEach(library) { item in
                        row(item, showsOrigin: true) {
                            Button {
                                guard selected.count < 5 else { return }
                                withAnimation { selected.append(item) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected.count < 5 ? CareToken.sage : CareToken.borderChip)
                            }
                            .buttonStyle(.plain)
                            .disabled(selected.count >= 5)
                            .accessibilityLabel("Add \(item.label)")
                        }
                        .listRowBackground(CareToken.card)
                    }
                } header: {
                    Text("Library: drafted, patient plan, and presets")
                }

                Section {
                    Button {
                        SharedCareStore.clearCuratedActivities()
                        postFeedNote("Care team switched \(name)'s daily list back to automatic.")
                        Task { await FirebaseSync.shared.publishCurrentState() }
                        onSaved()
                        dismiss()
                    } label: {
                        Text("Use automatic order instead")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CareToken.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(CareToken.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CareToken.gradient.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Daily five")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SharedCareStore.writeCuratedActivities(Array(selected.prefix(5)))
                        postFeedNote("Care team arranged \(name)'s daily five.")
                        Task { await FirebaseSync.shared.publishCurrentState() }
                        onSaved()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .onAppear {
            let saved = SharedCareStore.readCuratedActivities()
            // Re-resolve against the current pool so stale entries drop out.
            selected = saved.compactMap { savedItem in
                pool.first { $0.id == savedItem.id } ?? (savedItem.id.hasPrefix("careplan-orphan") ? nil : savedItem)
            }
        }
    }

    private var name: String {
        SharedCareStore.readSnapshot()?.patientName ?? "the patient"
    }

    private func postFeedNote(_ text: String) {
        var feed = SharedCareStore.readFeed()
        feed.insert(CareUpdate(text: text, kind: "activity"), at: 0)
        if feed.count > 50 { feed = Array(feed.prefix(50)) }
        SharedCareStore.writeFeed(feed)
    }

    private func row(_ item: CarePlanActivity, showsOrigin: Bool,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(careHex: item.tintHex))
                    .frame(width: 38, height: 38)
                Image(systemName: item.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(careHex: item.colorHex))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CareToken.heading)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if showsOrigin {
                        originTag(item)
                    }
                    Text(item.sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CareToken.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func originTag(_ item: CarePlanActivity) -> some View {
        let (label, color): (String, Color) = {
            if item.id.hasPrefix("preset.") { return ("PRESET", CareToken.muted2) }
            if item.id.hasPrefix("ssi.") { return ("PATIENT'S PLAN", CareToken.sageDeep) }
            if item.isPT { return ("PT", CareToken.primary) }
            return ("DRAFTED", CareToken.sage)
        }()
        Text(label)
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
