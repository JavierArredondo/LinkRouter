import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: RoutingCoordinator
    var body: some View {
        Toggle("Enabled", isOn: .constant(true)).disabled(true)
        Text(coordinator.handlerStatus).lineLimit(1)
        Text("Last routed: \(coordinator.lastRouted)").lineLimit(1)
        Divider()
        Button("Refresh destinations") { coordinator.refreshDestinations() }
        Button("Settings…") { coordinator.presentSettings() }
        Divider()
        Button("Quit LinkRouter") { NSApplication.shared.terminate(nil) }
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: RoutingCoordinator
    var body: some View {
        Form {
            Section("Routing") {
                Text(coordinator.handlerStatus).foregroundStyle(.secondary)
                HStack { Button("Use LinkRouter for web links") { coordinator.becomeDefaultHandler() }; Button("Refresh handler status") { coordinator.refreshHandlerStatus() } }
                Toggle("Show picker when no rule matches", isOn: Binding(get: { coordinator.configuration.askWhenNoMatch }, set: { value in coordinator.update { $0.askWhenNoMatch = value } }))
                Toggle("Enable local, redacted diagnostics", isOn: Binding(get: { coordinator.configuration.diagnosticsEnabled }, set: { value in coordinator.update { $0.diagnosticsEnabled = value } }))
                Picker("Default destination", selection: Binding(get: { coordinator.configuration.defaultDestinationID }, set: { id in coordinator.update { $0.defaultDestinationID = id } })) {
                    Text("None").tag(UUID?.none)
                    ForEach(coordinator.configuration.destinations) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Button("Refresh destinations") { coordinator.refreshDestinations() }
            }
            Section("Rules") { RuleList(coordinator: coordinator) }
            Section("Suggested from your routing history") { SuggestionsList(coordinator: coordinator) }
        }.padding().frame(width: 560, height: 520)
    }
}

struct OnboardingView: View {
    @ObservedObject var coordinator: RoutingCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 42)).foregroundStyle(.tint)
            Text("Route every link to the right browser").font(.title2.bold())
            Text("LinkRouter needs to become the default handler for web links. You can change this later in Settings.")
            Text(coordinator.handlerStatus).foregroundStyle(.secondary)
            HStack { Button("Use LinkRouter for web links") { coordinator.becomeDefaultHandler() }.buttonStyle(.borderedProminent); Button("Refresh destinations") { coordinator.refreshDestinations() } }
        }.padding(28).frame(width: 460)
    }
}

private struct RuleList: View {
    @ObservedObject var coordinator: RoutingCoordinator
    @State private var editingRule: Rule?
    @State private var showingPresets = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Add rule") { addRule() }
                Button("Add from presets…") { showingPresets = true }.disabled(coordinator.configuration.destinations.isEmpty)
                Text("Use the arrows to reorder rules").font(.caption).foregroundStyle(.secondary)
            }
            List {
            ForEach(coordinator.configuration.rules) { rule in
                HStack {
                    Toggle("", isOn: Binding(get: { rule.enabled }, set: { enabled in coordinator.update { config in if let index = config.rules.firstIndex(where: { $0.id == rule.id }) { config.rules[index].enabled = enabled } } }))
                    Button(rule.name) { editingRule = rule }.buttonStyle(.plain)
                    Spacer()
                    Text(destinationName(rule.targetID)).foregroundStyle(.secondary)
                    Button { move(rule, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(coordinator.configuration.rules.firstIndex(where: { $0.id == rule.id }) == 0)
                    Button { move(rule, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(coordinator.configuration.rules.last?.id == rule.id)
                }
            }
            .onDelete { indexes in coordinator.update { config in config.rules.remove(atOffsets: indexes); normalizeOrders(&config.rules) } }
            .onMove { indexes, target in coordinator.update { config in config.rules.move(fromOffsets: indexes, toOffset: target); normalizeOrders(&config.rules) } }
            }
        }
        .sheet(isPresented: $showingPresets) {
            PresetSheet(destinations: coordinator.configuration.destinations, existingRules: coordinator.configuration.rules) { presets, targetID in
                _ = coordinator.applyPresets(presets, to: targetID)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule, destinations: coordinator.configuration.destinations) { saved in
                coordinator.update { config in
                    if let index = config.rules.firstIndex(where: { $0.id == saved.id }) { config.rules[index] = saved }
                    else { config.rules.append(saved) }
                    normalizeOrders(&config.rules)
                }
            }
        }
    }
    private func addRule() { guard let target = coordinator.configuration.destinations.first else { return }; editingRule = Rule(name: "New rule", order: coordinator.configuration.rules.count, match: RuleMatch(host: "", hostMode: .exact), targetID: target.id) }
    private func move(_ rule: Rule, by offset: Int) {
        guard let index = coordinator.configuration.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let destination = index + offset
        guard coordinator.configuration.rules.indices.contains(destination) else { return }
        coordinator.update { config in let item = config.rules.remove(at: index); config.rules.insert(item, at: destination); normalizeOrders(&config.rules) }
    }
    private func destinationName(_ id: UUID) -> String { coordinator.configuration.destinations.first(where: { $0.id == id })?.displayName ?? "Missing destination" }
    private func normalizeOrders(_ rules: inout [Rule]) { for index in rules.indices { rules[index].order = index } }
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Rule
    let destinations: [Destination]
    let save: (Rule) -> Void
    init(rule: Rule, destinations: [Destination], save: @escaping (Rule) -> Void) { _rule = State(initialValue: rule); self.destinations = destinations; self.save = save }
    private var hostPrompt: String { rule.match.hostMode == .regex ? #"^(mail|drive)\.google\.com$"# : "github.com or *.example.com" }
    var body: some View {
        VStack(alignment: .leading) {
            Text("Rule").font(.title3.bold())
            Form {
                TextField("Name", text: $rule.name)
                TextField("Host", text: $rule.match.host, prompt: Text(hostPrompt))
                Picker("Host match", selection: $rule.match.hostMode) { Text("Exact host").tag(HostMode.exact); Text("Wildcard subdomains").tag(HostMode.wildcard); Text("Regex").tag(HostMode.regex) }
                if let error = RulePatternValidator.hostError(rule.match) { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Picker("Path condition", selection: $rule.match.pathMode) { Text("None").tag(PathMode?.none); Text("Prefix").tag(PathMode?.some(.prefix)); Text("Contains").tag(PathMode?.some(.contains)); Text("Regex").tag(PathMode?.some(.regex)) }
                if rule.match.pathMode != nil { TextField("Path", text: Binding(get: { rule.match.pathValue ?? "" }, set: { rule.match.pathValue = $0 })) }
                if let error = RulePatternValidator.pathError(rule.match) { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Picker("Open in", selection: $rule.targetID) { ForEach(destinations) { Text($0.displayName).tag($0.id) } }
                if rule.match.hostMode == .regex || rule.match.pathMode == .regex {
                    Text("A regex is ranked between an exact host and a wildcard. Host patterns match case-insensitively; path patterns do not.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines); rule.match.host = rule.match.host.trimmingCharacters(in: .whitespacesAndNewlines); save(rule); dismiss() }.buttonStyle(.borderedProminent).disabled(rule.match.host.isEmpty || destinations.isEmpty || !RulePatternValidator.isValid(rule.match)) }
        }.padding().frame(width: 440)
    }
}
