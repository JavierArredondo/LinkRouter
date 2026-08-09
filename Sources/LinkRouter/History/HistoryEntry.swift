import Foundation

enum HistoryOutcome: String, Codable, CaseIterable, Sendable {
    case rule       // A rule matched.
    case fallback   // No rule, sent to the default destination.
    case picker     // No rule, chosen by hand.
    case cancelled  // The picker was dismissed without choosing.
    case rejected   // Malformed or non-web URL.
    case failed     // A destination was chosen but would not open.

    var label: String {
        switch self {
        case .rule: return "matched a rule"
        case .fallback: return "default destination"
        case .picker: return "chosen in picker"
        case .cancelled: return "cancelled"
        case .rejected: return "rejected"
        case .failed: return "failed to open"
        }
    }

    var symbol: String {
        switch self {
        case .rule: return "arrow.triangle.branch"
        case .fallback: return "arrow.uturn.right"
        case .picker: return "hand.tap"
        case .cancelled: return "xmark.circle"
        case .rejected, .failed: return "exclamationmark.triangle"
        }
    }

    /// The outcomes that mean "no rule handled this", which is what makes a host worth suggesting.
    var isUnrouted: Bool { self == .picker || self == .fallback }
}

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let host: String
    let path: String
    let outcome: HistoryOutcome
    let destinationName: String?
    let destinationBundleIdentifier: String?
    let ruleName: String?

    var display: String { path.isEmpty || path == "/" ? host : host + path }

    /// Query strings are dropped on the way in rather than hidden on the way out: they carry session
    /// tokens, password-reset links and tracking parameters, and the safest place for those is nowhere.
    static func make(
        url: URL,
        date: Date,
        outcome: HistoryOutcome,
        destination: Destination?,
        ruleName: String?,
        id: UUID = UUID()
    ) -> HistoryEntry {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = (components?.host ?? url.host())?.lowercased() ?? url.absoluteString
        return HistoryEntry(
            id: id,
            date: date,
            host: host,
            path: components?.percentEncodedPath ?? "",
            outcome: outcome,
            destinationName: destination?.displayName,
            destinationBundleIdentifier: destination?.bundleIdentifier,
            ruleName: ruleName
        )
    }
}

struct HostSuggestion: Identifiable, Equatable, Sendable {
    let host: String
    let count: Int

    var id: String { host }
}

/// Encoding, parsing and derivation live apart from the actor that owns the file, so the on-disk
/// format stays covered by tests.
enum RouteHistoryLog {
    static let limit = 500
    /// Compacting on every append would rewrite the whole file each time, so the log is allowed to
    /// overshoot the limit and is trimmed in batches.
    static let compactionInterval = 100

    static func line(for entry: HistoryEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry), let json = String(data: data, encoding: .utf8) else { return nil }
        return json + "\n"
    }

    /// Unparseable lines are skipped rather than failing the whole read: a truncated final line from
    /// an interrupted write must not cost the user their entire history.
    static func entries(in text: String) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(HistoryEntry.self, from: data)
        }
    }

    static func trimmed(_ entries: [HistoryEntry], limit: Int = limit) -> [HistoryEntry] {
        entries.count <= limit ? entries : Array(entries.suffix(limit))
    }

    /// Only hosts that reached the picker or the default destination are suggested — a host that
    /// already matched a rule needs nothing. Exact-host rules are additionally excluded; judging
    /// whether a wildcard or regex already covers a host would mean running the engine, and a
    /// redundant suggestion is a cheaper mistake than a missing one.
    static func suggestions(from entries: [HistoryEntry], rules: [Rule], limit: Int) -> [HostSuggestion] {
        let covered = Set(rules.filter { $0.match.hostMode == .exact }
            .map { $0.match.host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        var counts: [String: Int] = [:]
        for entry in entries where entry.outcome.isUnrouted && !covered.contains(entry.host) {
            counts[entry.host, default: 0] += 1
        }
        let candidates = counts.map { HostSuggestion(host: $0.key, count: $0.value) }
        let ranked = candidates.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.host < rhs.host : lhs.count > rhs.count
        }
        return Array(ranked.prefix(limit))
    }
}
