import SwiftUI

struct PresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destinations: [Destination]
    let existingRules: [Rule]
    let apply: ([SitePreset], UUID) -> Void

    @State private var chosen: Set<String> = []
    @State private var targetID: UUID?

    private var selectedPresets: [SitePreset] { SitePresets.all.filter { chosen.contains($0.id) } }

    /// Counted with the same de-duplication the apply path uses, so the button never promises rules
    /// that will be skipped.
    private var newRuleCount: Int {
        guard let targetID else { return 0 }
        return SitePresets.rules(for: selectedPresets, targetID: targetID, existing: existingRules, startingOrder: 0).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add rules from presets").font(.title3.bold())
            ForEach(SitePresets.all) { preset in
                Toggle(isOn: Binding(
                    get: { chosen.contains(preset.id) },
                    set: { isOn in if isOn { chosen.insert(preset.id) } else { chosen.remove(preset.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.title)
                        Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Picker("Open in", selection: $targetID) {
                Text("Choose a destination").tag(UUID?.none)
                ForEach(destinations) { Text($0.displayName).tag(UUID?.some($0.id)) }
            }
            Text(summary).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add rules") {
                    if let targetID { apply(selectedPresets, targetID) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newRuleCount == 0)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private var summary: String {
        guard targetID != nil else { return "Pick a destination to continue." }
        guard !selectedPresets.isEmpty else { return "Pick at least one preset." }
        let total = selectedPresets.reduce(0) { $0 + $1.hosts.count }
        let skipped = total - newRuleCount
        if newRuleCount == 0 { return "All \(total) sites already have rules." }
        return skipped == 0
            ? "\(newRuleCount) rules will be created."
            : "\(newRuleCount) rules will be created, \(skipped) skipped because they already have rules."
    }
}

struct SuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: RoutingCoordinator
    @State private var targetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested from your routing history").font(.title3.bold())
            content
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }
        .padding()
        .frame(width: 460)
        .onAppear { coordinator.refreshSuggestions() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !coordinator.configuration.isHistoryEnabled {
                Label("Turn on history in the History tab to get suggestions from the sites you actually open.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if coordinator.suggestions.isEmpty {
                Text("No suggestions yet — they appear once links have opened without a rule matching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Open in", selection: $targetID) {
                    Text("Choose a destination").tag(UUID?.none)
                    ForEach(coordinator.configuration.destinations) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                ForEach(coordinator.suggestions) { suggestion in
                    HStack {
                        Text(suggestion.host)
                        Text("\(suggestion.count)×").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add rule") {
                            if let targetID { coordinator.addRule(forHost: suggestion.host, targetID: targetID) }
                        }
                        .disabled(targetID == nil)
                    }
                }
            }
        }
    }
}
