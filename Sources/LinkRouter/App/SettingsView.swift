import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: RoutingCoordinator

    var body: some View {
        TabView {
            GeneralTab(coordinator: coordinator)
                .tabItem { Label("General", systemImage: "gearshape") }
            RulesTab(coordinator: coordinator)
                .tabItem { Label("Rules", systemImage: "arrow.triangle.branch") }
            HistoryTab(coordinator: coordinator)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            AdvancedTab(coordinator: coordinator)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 620, height: 540)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var coordinator: RoutingCoordinator

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: coordinator.isDefaultHandler ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(coordinator.isDefaultHandler ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.isDefaultHandler ? "LinkRouter opens your web links" : "LinkRouter is not handling web links")
                        Text(coordinator.handlerStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if coordinator.isDefaultHandler {
                        Button("Recheck") { coordinator.refreshHandlerStatus() }
                    } else {
                        Button("Use LinkRouter") { coordinator.becomeDefaultHandler() }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Default destination", selection: Binding(
                    get: { coordinator.configuration.defaultDestinationID },
                    set: { id in coordinator.update { $0.defaultDestinationID = id } }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(coordinator.configuration.destinations) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Toggle("Ask when no rule matches", isOn: Binding(
                    get: { coordinator.configuration.askWhenNoMatch },
                    set: { value in coordinator.update { $0.askWhenNoMatch = value } }
                ))
            } footer: {
                Text(coordinator.configuration.askWhenNoMatch
                     ? "Links without a matching rule open the picker."
                     : "Links without a matching rule go straight to the default destination.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Last routed", value: coordinator.lastRouted)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Rules

private struct RulesTab: View {
    @ObservedObject var coordinator: RoutingCoordinator
    @State private var editingRule: Rule?
    @State private var showingPresets = false
    @State private var showingSuggestions = false
    @State private var selection: UUID?

    private var rules: [Rule] { coordinator.configuration.rules }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(rules) { rule in
                    RuleRow(
                        rule: rule,
                        destination: coordinator.configuration.destinations.first { $0.id == rule.targetID },
                        isFirst: rules.first?.id == rule.id,
                        isLast: rules.last?.id == rule.id,
                        setEnabled: { enabled in setEnabled(rule, enabled) },
                        move: { offset in move(rule, by: offset) },
                        edit: { editingRule = rule }
                    )
                    .tag(rule.id)
                }
                .onMove { indexes, target in
                    coordinator.update { config in
                        config.rules.move(fromOffsets: indexes, toOffset: target)
                        normalizeOrders(&config.rules)
                    }
                }
            }
            .listStyle(.inset)
            .overlay { if rules.isEmpty { emptyState } }

            Divider()
            toolbar
        }
        .sheet(isPresented: $showingPresets) {
            PresetSheet(destinations: coordinator.configuration.destinations, existingRules: rules) { presets, targetID in
                _ = coordinator.applyPresets(presets, to: targetID)
            }
        }
        .sheet(isPresented: $showingSuggestions) {
            SuggestionsSheet(coordinator: coordinator)
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No rules yet").font(.headline)
            Text("Every link will show the picker until you add one.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { addRule() } label: { Image(systemName: "plus") }
                .disabled(coordinator.configuration.destinations.isEmpty)
                .help("Add a rule")
            Button { deleteSelected() } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                .help("Delete the selected rule")
            Divider().frame(height: 14)
            Button("Presets…") { showingPresets = true }
                .disabled(coordinator.configuration.destinations.isEmpty)
            Button("Suggestions…") { showingSuggestions = true }
            Spacer()
            Text("Double-click to edit · drag to reorder")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func addRule() {
        guard let target = coordinator.configuration.destinations.first else { return }
        editingRule = Rule(name: "", order: rules.count, match: RuleMatch(host: "", hostMode: .exact), targetID: target.id)
    }

    private func deleteSelected() {
        guard let selection else { return }
        coordinator.update { config in
            config.rules.removeAll { $0.id == selection }
            normalizeOrders(&config.rules)
        }
        self.selection = nil
    }

    private func setEnabled(_ rule: Rule, _ enabled: Bool) {
        coordinator.update { config in
            if let index = config.rules.firstIndex(where: { $0.id == rule.id }) { config.rules[index].enabled = enabled }
        }
    }

    private func move(_ rule: Rule, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let target = index + offset
        guard rules.indices.contains(target) else { return }
        coordinator.update { config in
            let item = config.rules.remove(at: index)
            config.rules.insert(item, at: target)
            normalizeOrders(&config.rules)
        }
    }

    private func normalizeOrders(_ rules: inout [Rule]) {
        for index in rules.indices { rules[index].order = index }
    }
}

private struct RuleRow: View {
    let rule: Rule
    let destination: Destination?
    let isFirst: Bool
    let isLast: Bool
    let setEnabled: (Bool) -> Void
    let move: (Int) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: setEnabled)).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // The pattern, not the name: a rule called "wikipedia regex" says nothing about
                    // what it captures.
                    Text(rule.match.host.isEmpty ? "(no host)" : rule.match.host)
                        .font(rule.match.hostMode == .regex ? .body.monospaced() : .body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !rule.name.isEmpty, rule.name != rule.match.host {
                        Text(rule.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    Text(RuleSummary.description(rule.match))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    if let destination {
                        DestinationIcon(bundleIdentifier: destination.bundleIdentifier, size: 13)
                        Text(destination.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Missing destination").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(isFirst)
            Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(isLast)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
        .opacity(rule.enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }
}

// MARK: - History

private struct HistoryTab: View {
    @ObservedObject var coordinator: RoutingCoordinator
    @State private var search = ""

    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return coordinator.historyEntries }
        return coordinator.historyEntries.filter {
            $0.display.lowercased().contains(query) || ($0.destinationName ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by link or destination", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(filtered) { entry in HistoryRow(entry: entry) }
            }
            .listStyle(.inset)
            .overlay { if filtered.isEmpty { emptyState } }

            Divider()

            HStack {
                Toggle("Keep a history of opened links", isOn: Binding(
                    get: { coordinator.configuration.isHistoryEnabled },
                    set: { value in coordinator.update { $0.historyEnabled = value } }
                ))
                Spacer()
                Text("last \(RouteHistoryLog.limit)").font(.caption).foregroundStyle(.secondary)
                Button("Clear") { coordinator.clearHistory() }
                    .disabled(coordinator.historyEntries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { coordinator.refreshHistory() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
            Text(coordinator.configuration.isHistoryEnabled ? "No links yet" : "History is off").font(.headline)
            Text(coordinator.configuration.isHistoryEnabled
                 ? "Links you open will appear here. Query strings are never recorded."
                 : "Turn it back on below to start recording again.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.outcome.symbol)
                .foregroundStyle(entry.outcome == .rejected || entry.outcome == .failed ? Color.orange : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.display).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(entry.ruleName.map { "rule: \($0)" } ?? entry.outcome.label)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let name = entry.destinationName, let bundle = entry.destinationBundleIdentifier {
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        DestinationIcon(bundleIdentifier: bundle, size: 13)
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject var coordinator: RoutingCoordinator

    var body: some View {
        Form {
            Section("Destinations") {
                ForEach(coordinator.configuration.destinations) { destination in
                    HStack(spacing: 10) {
                        DestinationIcon(bundleIdentifier: destination.bundleIdentifier, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(destination.displayName)
                            Text(subtitle(destination)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !destination.isWebBrowser {
                            Text("not a browser").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Refresh destinations") { coordinator.refreshDestinations() }
            }
        }
        .formStyle(.grouped)
    }

    private func subtitle(_ destination: Destination) -> String {
        if let profile = destination.chromeProfileDirectory { return "Chrome profile · \(profile)" }
        return destination.bundleIdentifier
    }
}

// MARK: - Rule editor

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Rule
    let destinations: [Destination]
    let save: (Rule) -> Void

    init(rule: Rule, destinations: [Destination], save: @escaping (Rule) -> Void) {
        _rule = State(initialValue: rule)
        self.destinations = destinations
        self.save = save
    }

    private var hostPrompt: String {
        rule.match.hostMode == .regex ? #"^(mail|drive)\.google\.com$"# : "github.com or *.example.com"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rule").font(.title3.bold())
            Form {
                Section {
                    TextField("Host", text: $rule.match.host, prompt: Text(hostPrompt))
                        .font(rule.match.hostMode == .regex ? .body.monospaced() : .body)
                    Picker("Match", selection: $rule.match.hostMode) {
                        Text("Exact host").tag(HostMode.exact)
                        Text("Wildcard subdomains").tag(HostMode.wildcard)
                        Text("Regex").tag(HostMode.regex)
                    }
                    if let error = RulePatternValidator.hostError(rule.match) {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Path condition", selection: $rule.match.pathMode) {
                        Text("None").tag(PathMode?.none)
                        Text("Prefix").tag(PathMode?.some(.prefix))
                        Text("Contains").tag(PathMode?.some(.contains))
                        Text("Regex").tag(PathMode?.some(.regex))
                    }
                    if rule.match.pathMode != nil {
                        TextField("Path", text: Binding(
                            get: { rule.match.pathValue ?? "" },
                            set: { rule.match.pathValue = $0 }
                        ))
                    }
                    if let error = RulePatternValidator.pathError(rule.match) {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Open in", selection: $rule.targetID) {
                        ForEach(destinations) { Text($0.displayName).tag($0.id) }
                    }
                    TextField("Name (optional)", text: $rule.name, prompt: Text("Defaults to the host"))
                }
                if rule.match.hostMode == .regex || rule.match.pathMode == .regex {
                    Text("A regex ranks between an exact host and a wildcard. Host patterns match case-insensitively; path patterns do not.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Text(RuleSummary.description(rule.match)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    rule.match.host = rule.match.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(rule.match.host.isEmpty || destinations.isEmpty || !RulePatternValidator.isValid(rule.match))
            }
        }
        .padding()
        .frame(width: 470)
    }
}
