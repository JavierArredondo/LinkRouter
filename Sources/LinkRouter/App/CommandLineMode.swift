import AppKit
import Foundation

/// A terminal interface over the same routing core the app uses.
///
/// Implemented as a mode of the app binary rather than a separate executable target: the routing
/// core lives in this target, and a second target could only reach it by promoting the whole pure
/// layer to a public library API. That is a lot of surface to freeze for a convenience command.
enum CommandLineMode {
    /// Verbs recognised before AppKit starts. Anything else — including the argument macOS itself
    /// passes on launch — falls through to the GUI.
    static let verbs: Set<String> = ["open", "test", "rules", "help", "--help", "-h"]

    static func shouldHandle(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return verbs.contains(first)
    }

    static func run(_ arguments: [String]) -> Never {
        let verb = arguments.first ?? "help"
        let rest = Array(arguments.dropFirst())
        switch verb {
        case "open": exit(open(rest))
        case "test": exit(test(rest))
        case "rules": exit(listRules())
        default:
            print(usage)
            exit(0)
        }
    }

    private static let usage = """
    linkrouter — route a link the way LinkRouter would

      linkrouter open <url>    open the link in the destination its rules select
      linkrouter test <url>    show which rule wins, and why, without opening anything
      linkrouter rules         list the configured rules in precedence order
      linkrouter help          this message

    Reads the same configuration as the app: ~/Library/Application Support/LinkRouter.
    """

    // MARK: - Commands

    private static func open(_ arguments: [String]) -> Int32 {
        guard let value = arguments.first, let url = URL(string: value) else {
            FileHandle.standardError.write(Data("usage: linkrouter open <url>\n".utf8))
            return 2
        }
        let configuration = loadConfiguration()
        let explanation = explain(url, configuration)
        if let error = explanation.error {
            FileHandle.standardError.write(Data("rejected: \(error)\n".utf8))
            return 1
        }
        guard let destination = explanation.destination else {
            // The picker is a GUI affordance; in a terminal, refusing beats guessing.
            FileHandle.standardError.write(Data("no rule matches \(url.host() ?? value) — the app would show the picker\n".utf8))
            return 1
        }
        let target = configuration.isTrackingRemovalEnabled ? TrackingParameters.strip(from: url) : url
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: destination.bundleIdentifier) else {
            FileHandle.standardError.write(Data("\(destination.displayName) is not installed\n".utf8))
            return 1
        }
        let configurationOptions = NSWorkspace.OpenConfiguration()
        if let profile = destination.chromiumProfileDirectory {
            configurationOptions.createsNewApplicationInstance = true
            configurationOptions.arguments = ["--profile-directory=\(profile)", target.absoluteString]
        }
        let group = DispatchGroup()
        var failure: Error?
        group.enter()
        if destination.chromiumProfileDirectory != nil {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configurationOptions) { _, error in
                failure = error
                group.leave()
            }
        } else {
            NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: configurationOptions) { _, error in
                failure = error
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 20)
        if let failure {
            FileHandle.standardError.write(Data("could not open: \(failure.localizedDescription)\n".utf8))
            return 1
        }
        print("\(target.host() ?? value) → \(destination.displayName)")
        return 0
    }

    private static func test(_ arguments: [String]) -> Int32 {
        guard let value = arguments.first, let url = URL(string: value) else {
            FileHandle.standardError.write(Data("usage: linkrouter test <url>\n".utf8))
            return 2
        }
        let explanation = explain(url, loadConfiguration())
        if let error = explanation.error {
            print("rejected: \(error)")
            return 1
        }
        print("host      \(explanation.host ?? "—")")
        print("path      \(explanation.path?.isEmpty == false ? explanation.path! : "/")")
        if let stripped = explanation.strippedURL { print("cleaned   \(stripped.absoluteString)") }
        if explanation.candidates.isEmpty {
            print("rules     none match — the picker would open")
        } else {
            for candidate in explanation.candidates {
                let marker = candidate.isWinner ? "→" : " "
                print("rules   \(marker) \(candidate.rule.match.host)  (\(RuleSummary.description(candidate.rule.match)))")
            }
        }
        print("result    \(explanation.destination?.displayName ?? "picker")")
        return 0
    }

    private static func listRules() -> Int32 {
        let configuration = loadConfiguration()
        guard !configuration.rules.isEmpty else {
            print("no rules configured")
            return 0
        }
        let names = Dictionary(configuration.destinations.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        for rule in configuration.rules.sorted(by: { $0.order < $1.order }) {
            let state = rule.enabled ? " " : "·"
            print("\(state) \(rule.match.host)")
            print("    \(RuleSummary.description(rule.match)) → \(names[rule.targetID] ?? "missing destination")")
        }
        return 0
    }

    // MARK: - Support

    private static func explain(_ url: URL, _ configuration: AppConfiguration) -> RouteExplanation {
        // Installed identifiers come from Launch Services, the same source the app uses, so the CLI
        // reports "not installed" for exactly the destinations the app would refuse.
        let installed = Set(["https://example.com", "http://example.com"]
            .compactMap(URL.init(string:))
            .flatMap { NSWorkspace.shared.urlsForApplications(toOpen: $0) }
            .compactMap { Bundle(url: $0)?.bundleIdentifier })
        return RoutePlayground.explain(
            url,
            configuration: configuration,
            availableBundleIdentifiers: installed,
            ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.linkrouter.app"
        )
    }

    /// Read directly rather than through `ConfigurationStore`: that is an actor, and awaiting it
    /// from a synchronous entry point before AppKit starts buys nothing here.
    private static func loadConfiguration() -> AppConfiguration {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkRouter", isDirectory: true)
            .appendingPathComponent("configuration.json")
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        return configuration
    }
}
