import Foundation

/// Explains what the router would do with a URL, without doing it.
///
/// The engine gained regex and specificity ranking, which makes "why did this link go there?" a
/// real question. Answering it by reading the rule list is guesswork; this answers it from the same
/// code that routes. Pure, so the explanation cannot drift from the decision.
struct RouteExplanation: Equatable, Sendable {
    struct Candidate: Equatable, Sendable {
        let rule: Rule
        let isWinner: Bool
    }

    let error: RouteError?
    let host: String?
    let path: String?
    /// Every enabled rule that matched, most specific first. More than one is normal — the ranking
    /// is what decides, and seeing the losers is how a surprising result gets diagnosed.
    let candidates: [Candidate]
    let destination: Destination?
    /// Non-nil only when stripping actually changed the URL.
    let strippedURL: URL?

    var matchedRule: Rule? { candidates.first { $0.isWinner }?.rule }
}

enum RoutePlayground {
    static func explain(
        _ url: URL,
        configuration: AppConfiguration,
        availableBundleIdentifiers: Set<String>,
        ownBundleIdentifier: String
    ) -> RouteExplanation {
        switch URLNormalizer.normalize(url) {
        case .failure(let error):
            return RouteExplanation(error: error, host: nil, path: nil, candidates: [], destination: nil, strippedURL: nil)
        case .success(let normalized):
            let engine = RuleEngine()
            let winner = engine.match(normalized, rules: configuration.rules)
            // Re-running the engine per rule keeps this honest: a candidate is anything the real
            // matcher accepts, not a re-implementation of the matching rules.
            let matching = configuration.rules.filter { rule in
                engine.match(normalized, rules: [rule]) != nil
            }
            let ranked = matching.sorted { lhs, rhs in
                engine.match(normalized, rules: [lhs, rhs])?.id == lhs.id
            }
            let decision = Router(ownBundleIdentifier: ownBundleIdentifier)
                .decide(url, configuration: configuration, availableBundleIdentifiers: availableBundleIdentifiers)
            let destination: Destination?
            switch decision {
            case .open(_, let target, _): destination = target
            case .ask, .reject: destination = nil
            }
            let stripped = configuration.isTrackingRemovalEnabled ? TrackingParameters.strip(from: url) : url
            return RouteExplanation(
                error: nil,
                host: normalized.host,
                path: normalized.path,
                candidates: ranked.map { RouteExplanation.Candidate(rule: $0, isWinner: $0.id == winner?.id) },
                destination: destination,
                strippedURL: stripped == url ? nil : stripped
            )
        }
    }
}
