import Foundation

/// Patterns are validated where they are authored, so an uncompilable regex is refused at save time
/// instead of silently matching nothing at routing time.
enum RulePatternValidator {
    static func hostError(_ match: RuleMatch) -> String? {
        guard match.hostMode == .regex else { return nil }
        return error(in: match.host.trimmingCharacters(in: .whitespacesAndNewlines), label: "Host")
    }

    static func pathError(_ match: RuleMatch) -> String? {
        guard match.pathMode == .regex, let value = match.pathValue else { return nil }
        return error(in: value, label: "Path")
    }

    static func isValid(_ match: RuleMatch) -> Bool { hostError(match) == nil && pathError(match) == nil }

    private static func error(in pattern: String, label: String) -> String? {
        guard !pattern.isEmpty else { return "\(label) pattern is empty" }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return "\(label) pattern is not a valid regular expression"
        }
    }
}
