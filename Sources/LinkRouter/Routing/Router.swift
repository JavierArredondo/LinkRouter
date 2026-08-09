import Foundation

struct Router: Sendable {
    let ruleEngine = RuleEngine()
    let ownBundleIdentifier: String

    func decide(_ url: URL, configuration: AppConfiguration, availableBundleIdentifiers: Set<String>) -> RouteDecision {
        switch URLNormalizer.normalize(url) {
        case .failure(let error): return .reject(url, error)
        case .success(let normalized):
            if let rule = ruleEngine.match(normalized, rules: configuration.rules) {
                guard let destination = configuration.destinations.first(where: { $0.id == rule.targetID }) else {
                    return .ask(url, available(configuration, availableBundleIdentifiers), .unavailableDestination(rule.targetID))
                }
                guard destination.bundleIdentifier != ownBundleIdentifier else { return .ask(url, available(configuration, availableBundleIdentifiers), .recursiveDestination) }
                guard availableBundleIdentifiers.contains(destination.bundleIdentifier) else {
                    return .ask(url, available(configuration, availableBundleIdentifiers), .unavailableDestination(destination.id))
                }
                return .open(url, destination, rule)
            }
            let candidates = available(configuration, availableBundleIdentifiers)
            if !configuration.askWhenNoMatch, let id = configuration.defaultDestinationID,
               let destination = candidates.first(where: { $0.id == id }) {
                return .open(url, destination, nil)
            }
            return .ask(url, candidates, nil)
        }
    }

    private func available(_ configuration: AppConfiguration, _ ids: Set<String>) -> [Destination] {
        configuration.destinations.filter { $0.bundleIdentifier != ownBundleIdentifier && ids.contains($0.bundleIdentifier) }
    }
}
