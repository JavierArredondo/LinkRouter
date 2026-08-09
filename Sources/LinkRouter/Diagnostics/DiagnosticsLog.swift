import Foundation

struct HostSuggestion: Identifiable, Equatable, Sendable {
    let host: String
    let count: Int

    var id: String { host }
}

/// Parsing lives apart from the actor that writes the log so the format stays covered by tests.
enum DiagnosticsLog {
    static func hostCounts(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            guard let field = line.split(separator: " ").first(where: { $0.hasPrefix("host=") }) else { continue }
            let host = String(field.dropFirst("host=".count)).lowercased()
            guard !host.isEmpty else { continue }
            counts[host, default: 0] += 1
        }
        return counts
    }

    /// Hosts already covered by a rule are dropped — suggesting what is already configured is noise.
    /// Only exact-host rules are treated as coverage; deciding whether a wildcard or regex rule
    /// already handles a host would mean running the engine, and a redundant suggestion is a far
    /// cheaper mistake than a missing one.
    static func suggestions(hostCounts: [String: Int], rules: [Rule], limit: Int) -> [HostSuggestion] {
        let covered = Set(rules.filter { $0.match.hostMode == .exact }
            .map { $0.match.host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let candidates: [HostSuggestion] = hostCounts.compactMap { host, count in
            covered.contains(host) ? nil : HostSuggestion(host: host, count: count)
        }
        let ranked = candidates.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.host < rhs.host : lhs.count > rhs.count
        }
        return Array(ranked.prefix(limit))
    }
}
