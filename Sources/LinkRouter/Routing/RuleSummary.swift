import Foundation

/// Human-readable descriptions of what a rule actually matches.
///
/// A rule's `name` is free text and often says nothing useful ("wikipedia regex"), so the rule list
/// shows the real condition instead. Kept pure so the wording stays covered by tests.
enum RuleSummary {
    static func hostLabel(_ match: RuleMatch) -> String {
        switch match.hostMode {
        case .exact: return "exact host"
        case .wildcard: return "subdomains"
        case .regex: return "regex"
        }
    }

    static func pathLabel(_ match: RuleMatch) -> String {
        guard let mode = match.pathMode, let value = match.pathValue, !value.isEmpty else { return "any path" }
        switch mode {
        case .prefix: return "path starts with \(value)"
        case .contains: return "path contains \(value)"
        case .regex: return "path matches \(value)"
        }
    }

    /// Only the last path component of the bundle identifier: "com.tinyspeck.slackmacgap" is noise
    /// in a list, "slackmacgap" is recognisable.
    static func sourceLabel(_ match: RuleMatch) -> String? {
        guard let identifier = match.sourceBundleIdentifier, !identifier.isEmpty else { return nil }
        return "from \(identifier.split(separator: ".").last.map(String.init) ?? identifier)"
    }

    static func description(_ match: RuleMatch) -> String {
        [hostLabel(match), pathLabel(match), sourceLabel(match)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
