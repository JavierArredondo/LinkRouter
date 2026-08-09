import Foundation

struct RuleEngine: Sendable {
    /// User-authored patterns are matched on the main thread while routing is serialized, so a
    /// pathological pattern would freeze both the UI and every queued link. Capping the scanned text
    /// bounds the damage to pattern complexity rather than URL length.
    static let maximumMatchLength = 2048

    func match(_ normalizedURL: NormalizedURL, rules: [Rule]) -> Rule? {
        // Compiled once per evaluation rather than once per rule: the same pattern often repeats,
        // and keeping the cache local avoids making this otherwise pure type stateful.
        var cache: [String: NSRegularExpression?] = [:]
        func expression(_ pattern: String, _ caseInsensitive: Bool) -> NSRegularExpression? {
            let key = (caseInsensitive ? "i:" : "s:") + pattern
            if let cached = cache[key] { return cached }
            let compiled = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
            cache[key] = compiled
            return compiled
        }
        return rules.filter(\.enabled)
            .filter { matches($0.match, url: normalizedURL, expression: expression) }
            .sorted { lhs, rhs in
                let left = specificity(lhs.match)
                let right = specificity(rhs.match)
                return left == right ? lhs.order < rhs.order : left > right
            }
            .first
    }

    private func matches(_ match: RuleMatch, url: NormalizedURL, expression: (String, Bool) -> NSRegularExpression?) -> Bool {
        let trimmedHost = match.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostMatches: Bool
        switch match.hostMode {
        case .exact: hostMatches = url.host == trimmedHost.lowercased()
        case .wildcard:
            let configured = trimmedHost.lowercased()
            let suffix = configured.hasPrefix("*.") ? String(configured.dropFirst(2)) : configured
            hostMatches = url.host.hasSuffix("." + suffix) // Explicitly excludes the apex.
        case .regex:
            // Deliberately not lowercased: case-folding a pattern would turn `\D` into `\d` and
            // silently invert its meaning. Case-insensitivity is a matching option instead, which
            // mirrors how exact host comparison is case-insensitive by normalization.
            hostMatches = matches(pattern: trimmedHost, in: url.host, caseInsensitive: true, expression: expression)
        }
        guard hostMatches else { return false }
        guard let mode = match.pathMode, let value = match.pathValue, !value.isEmpty else { return true }
        switch mode {
        case .prefix: return url.path.hasPrefix(value)
        case .contains: return url.path.contains(value)
        // Case-sensitive, consistent with the prefix and contains comparisons above.
        case .regex: return matches(pattern: value, in: url.path, caseInsensitive: false, expression: expression)
        }
    }

    private func matches(pattern: String, in value: String, caseInsensitive: Bool, expression: (String, Bool) -> NSRegularExpression?) -> Bool {
        // A pattern that fails to compile must match nothing. Matching everything would silently
        // hijack every link the moment a rule is saved with a typo.
        guard let regex = expression(pattern, caseInsensitive) else { return false }
        let subject = String(value.prefix(RuleEngine.maximumMatchLength))
        return regex.firstMatch(in: subject, options: [], range: NSRange(subject.startIndex..., in: subject)) != nil
    }

    /// Ranked by specificity, with ties broken on user ordering. A regex is deliberate but of
    /// unknowable breadth, so it sits between an exact host and a wildcard.
    private func specificity(_ match: RuleMatch) -> Int {
        let host: Int
        switch match.hostMode {
        case .exact: host = 20
        case .regex: host = 15
        case .wildcard: host = 10
        }
        return host + (match.pathMode == nil ? 0 : 1)
    }
}
