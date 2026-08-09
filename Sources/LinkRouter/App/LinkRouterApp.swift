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
    private let store = ConfigurationStore()
    private let registry = BrowserRegistry()
    private let launcher = TargetLauncher()
    private let handlerService = DefaultHandlerService()
    private let diagnostics = Diagnostics()
    private lazy var router = Router(ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.example.LinkRouter")
    private var queue: [URL] = []
    private var isProcessing = false
    private let picker = QuickPickerController()
    private let settingsWindow = HostedWindowController()
    private let onboardingWindow = HostedWindowController()

    private init() { Task { configuration = await store.load(); refreshDestinations(); refreshHandlerStatus() } }

    func receive(_ urls: [URL]) { queue.append(contentsOf: urls); processNext() }
    func refreshDestinations() {
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

    func refreshSuggestions() {
        Task {
            let counts = await diagnostics.hostCounts()
            self.suggestions = DiagnosticsLog.suggestions(hostCounts: counts, rules: self.configuration.rules, limit: 8)
        }
    }
    func refreshHandlerStatus() { handlerStatus = handlerService.currentStatus(ownBundleIdentifier: router.ownBundleIdentifier) }
    var isDefaultWebHandler: Bool { handlerService.isDefaultForWeb(ownBundleIdentifier: router.ownBundleIdentifier) }

    func presentSettings() {
        refreshHandlerStatus()
        settingsWindow.show(title: "LinkRouter Settings") { SettingsView(coordinator: self) }
    }

    /// Only on a machine where LinkRouter is not yet the handler — a menu-bar utility that pops a
    /// window on every login is a nuisance.
    func presentOnboardingIfNeeded() {
        guard !isDefaultWebHandler else { return }
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
            record(url, outcome: "open destination=\(destination.bundleIdentifier) rule=\(rule?.id.uuidString ?? "default")")
            launch(url, destination)
        case .ask(let url, let candidates, let issue):
            picker.show(url: url, destinations: candidates, message: issue.map { "The saved destination is unavailable (\($0))." }) { [weak self] destination, remember in
                guard let self else { return }
                if let destination { if remember { self.remember(url: url, destination: destination) }; self.launch(url, destination) }
                else { self.finish() }
            }
        case .reject(let url, let error): record(url, outcome: "reject error=\(error)"); lastRouted = "Could not route link: \(error)"; finish()
        }
    }
    private func launch(_ url: URL, _ destination: Destination) {
        Task {
            let error = await launcher.launch(url, in: destination)
            self.lastRouted = error == nil ? "\(url.host() ?? url.absoluteString) → \(destination.displayName)" : "Could not open \(destination.displayName)"
            self.finish()
        }
    }
    private func remember(url: URL, destination: Destination) {
        guard case .success(let normalized) = URLNormalizer.normalize(url) else { return }
        configuration.rules.append(Rule(name: normalized.host, order: configuration.rules.count, match: RuleMatch(host: normalized.host, hostMode: .exact), targetID: destination.id)); persist()
    }
    private func record(_ url: URL, outcome: String) {
        guard configuration.diagnosticsEnabled, let host = url.host()?.lowercased() else { return }
        Task { await diagnostics.record(host: host, outcome: outcome) }
    }
    private func finish() { isProcessing = false; processNext() }
    private func persist() { let snapshot = configuration; Task { try? await store.save(snapshot) } }
}
