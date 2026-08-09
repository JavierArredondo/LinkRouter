import AppKit
import SwiftUI

@main
struct LinkRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = RoutingCoordinator.shared

    /// The menu-bar item is the only SwiftUI scene; every window is created explicitly by
    /// `HostedWindowController`. See that type for why the scene-based windows were dropped.
    var body: some Scene {
        MenuBarExtra("LinkRouter", systemImage: "arrow.triangle.branch") { MenuBarView(coordinator: coordinator) }
            .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in RoutingCoordinator.shared.presentOnboardingIfNeeded() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in RoutingCoordinator.shared.receive(urls) }
    }

    /// Without this, launching an already-running menu-bar app looks like nothing happened: there is
    /// no Dock icon, no app menu, and therefore no ⌘, either.
    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in RoutingCoordinator.shared.presentSettings() }
        return true
    }
}

@MainActor
final class RoutingCoordinator: ObservableObject {
    static let shared = RoutingCoordinator()
    @Published private(set) var configuration = AppConfiguration()
    @Published var lastRouted: String = "No links routed yet"
    @Published var handlerStatus = "Checking default handler…"
    @Published private(set) var suggestions: [HostSuggestion] = []
    @Published private(set) var isDefaultHandler = false
    @Published private(set) var historyEntries: [HistoryEntry] = []
    private let store = ConfigurationStore()
    private let registry = BrowserRegistry()
    private let launcher = TargetLauncher()
    private let handlerService = DefaultHandlerService()
    private let history = RouteHistoryStore()
    private lazy var router = Router(ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.example.LinkRouter")
    private var queue: [URL] = []
    private var isProcessing = false
    private let picker = QuickPickerController()
    private let settingsWindow = HostedWindowController()
    private let onboardingWindow = HostedWindowController()

    private init() { Task { configuration = await store.load(); refreshDestinations(); refreshHandlerStatus() } }

    func receive(_ urls: [URL]) { queue.append(contentsOf: urls); processNext() }
    func refreshDestinations() {
        DestinationIcons.invalidate() // An app may have moved or been updated since the last scan.
        let found = registry.discoveredDestinations(excluding: router.ownBundleIdentifier)
        // Keyed by identity, not bundle id: Chrome profiles share one bundle id, and the same app can be
        // registered from two paths. `uniquingKeysWith` because the unique-keys initializer traps on collisions.
        let existing = Dictionary(configuration.destinations.map { ($0.identityKey, $0) }, uniquingKeysWith: { first, _ in first })
        // Keep the stored id, because rules target it — but take name and metadata from discovery, so
        // renamed browsers and profiles update and newly introduced metadata keys actually land.
        let refreshed = found.map { fresh -> Destination in
            guard let old = existing[fresh.identityKey] else { return fresh }
            return Destination(id: old.id, displayName: fresh.displayName, bundleIdentifier: fresh.bundleIdentifier, kind: fresh.kind, metadata: fresh.metadata)
        }
        // Preserve removed browsers so rules remain repairable rather than silently disappearing.
        let unavailable = configuration.destinations.filter { old in !found.contains(where: { $0.identityKey == old.identityKey }) }
        configuration.destinations = refreshed + unavailable
        persist()
    }
    func update(_ mutate: (inout AppConfiguration) -> Void) { mutate(&configuration); persist() }

    func applyPresets(_ presets: [SitePreset], to targetID: UUID) -> Int {
        let created = SitePresets.rules(for: presets, targetID: targetID, existing: configuration.rules, startingOrder: configuration.rules.count)
        guard !created.isEmpty else { return 0 }
        update { $0.rules.append(contentsOf: created) }
        refreshSuggestions()
        return created.count
    }

    func addRule(forHost host: String, targetID: UUID) {
        update { $0.rules.append(Rule(name: host, order: $0.rules.count, match: RuleMatch(host: host, hostMode: .exact), targetID: targetID)) }
        refreshSuggestions()
    }

    func explain(_ url: URL) -> RouteExplanation {
        RoutePlayground.explain(url,
                                configuration: configuration,
                                availableBundleIdentifiers: registry.installedBundleIdentifiers(),
                                ownBundleIdentifier: router.ownBundleIdentifier)
    }

    /// Re-opens a link straight from the history, in a destination chosen by hand.
    ///
    /// Deliberately bypasses the router: routing it again would send it right back where it already
    /// went, which is the thing the user is correcting. It also stays out of the serial queue,
    /// because nothing modal is involved. The recorded entry carries no query string by design, so
    /// this reopens the page rather than the exact original link.
    func reopen(_ entry: HistoryEntry, in destination: Destination) {
        guard let url = URL(string: "https://\(entry.host)\(entry.path)") else { return }
        Task {
            let error = await launcher.launch(url, in: destination)
            self.record(url, outcome: error == nil ? .picker : .failed, destination: destination, ruleName: nil)
            self.lastRouted = error == nil
                ? "\(entry.host) → \(destination.displayName)"
                : "Could not open \(destination.displayName)"
            self.refreshHistory()
        }
    }

    func exportConfiguration(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }

    /// Rules reference destinations by id, and those ids are generated per machine, so an imported
    /// configuration keeps its rules but its destinations are reconciled against what is installed
    /// here. A rule whose destination does not exist degrades to the picker rather than being lost.
    func importConfiguration(from url: URL) throws {
        let imported = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: url))
        configuration = imported
        refreshDestinations()
        refreshHistory()
    }

    func refreshHistory() {
        Task {
            let entries = await history.entries()
            self.historyEntries = entries.reversed() // Newest first for display.
            self.suggestions = RouteHistoryLog.suggestions(from: entries, rules: self.configuration.rules, limit: 8)
        }
    }

    func clearHistory() {
        Task {
            await history.clear()
            self.historyEntries = []
            self.suggestions = []
        }
    }

    func refreshSuggestions() { refreshHistory() }
    /// Published rather than computed on demand: the settings view reads it on every render, and each
    /// check is two Launch Services round-trips.
    func refreshHandlerStatus() {
        handlerStatus = handlerService.currentStatus(ownBundleIdentifier: router.ownBundleIdentifier)
        isDefaultHandler = handlerService.isDefaultForWeb(ownBundleIdentifier: router.ownBundleIdentifier)
    }

    func presentSettings() {
        refreshHandlerStatus()
        settingsWindow.show(title: "LinkRouter Settings") { SettingsView(coordinator: self) }
    }

    /// Only on a machine where LinkRouter is not yet the handler — a menu-bar utility that pops a
    /// window on every login is a nuisance.
    func presentOnboardingIfNeeded() {
        refreshHandlerStatus()
        guard !isDefaultHandler else { return }
        onboardingWindow.show(title: "LinkRouter") { OnboardingView(coordinator: self) }
    }
    func becomeDefaultHandler() {
        Task {
            do { try await handlerService.setLinkRouterAsDefault(); refreshHandlerStatus() }
            catch { handlerStatus = "Default-handler request failed: \(error.localizedDescription)" }
        }
    }

    private func processNext() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let url = queue.removeFirst()
        switch router.decide(url, configuration: configuration, availableBundleIdentifiers: registry.installedBundleIdentifiers()) {
        case .open(let url, let destination, let rule):
            launch(url, destination, outcome: rule == nil ? .fallback : .rule, ruleName: rule?.name)
        case .ask(let url, let candidates, let issue):
            picker.show(url: url, destinations: candidates, message: issue.map { "The saved destination is unavailable (\($0))." }) { [weak self] destination, remember in
                guard let self else { return }
                if let destination {
                    if remember { self.remember(url: url, destination: destination) }
                    self.launch(url, destination, outcome: .picker, ruleName: nil)
                } else {
                    self.record(url, outcome: .cancelled, destination: nil, ruleName: nil)
                    self.finish()
                }
            }
        case .reject(let url, let error):
            record(url, outcome: .rejected, destination: nil, ruleName: nil)
            lastRouted = "Could not route link: \(error)"
            finish()
        }
    }
    private func launch(_ url: URL, _ destination: Destination, outcome: HistoryOutcome, ruleName: String?) {
        // Cleaned at the last moment: rules match on host and path, so stripping never changes which
        // rule won, and the history records the link the user actually clicked.
        let target = configuration.isTrackingRemovalEnabled ? TrackingParameters.strip(from: url) : url
        Task {
            let error = await launcher.launch(target, in: destination)
            // Recorded after the attempt, so the history reflects what happened rather than what was intended.
            self.record(url, outcome: error == nil ? outcome : .failed, destination: destination, ruleName: ruleName)
            self.lastRouted = error == nil ? "\(url.host() ?? url.absoluteString) → \(destination.displayName)" : "Could not open \(destination.displayName)"
            self.finish()
        }
    }
    private func remember(url: URL, destination: Destination) {
        guard case .success(let normalized) = URLNormalizer.normalize(url) else { return }
        configuration.rules.append(Rule(name: normalized.host, order: configuration.rules.count, match: RuleMatch(host: normalized.host, hostMode: .exact), targetID: destination.id)); persist()
    }
    private func record(_ url: URL, outcome: HistoryOutcome, destination: Destination?, ruleName: String?) {
        guard configuration.isHistoryEnabled else { return }
        let entry = HistoryEntry.make(url: url, date: Date(), outcome: outcome, destination: destination, ruleName: ruleName)
        Task { await history.record(entry) }
    }
    private func finish() { isProcessing = false; processNext() }
    private func persist() { let snapshot = configuration; Task { try? await store.save(snapshot) } }
}
