import Foundation

struct PresetHost: Equatable, Sendable {
    let host: String
    let mode: HostMode

    init(_ host: String, _ mode: HostMode = .exact) {
        self.host = host
        self.mode = mode
    }
}

struct SitePreset: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let hosts: [PresetHost]
}

/// A bundled catalog rather than a fetched one: the product has no network dependency, and rules
/// must stay deterministic.
///
/// The catalog itself lives in `Presets/presets.json` and is compiled in via
/// `SitePresets+Generated.swift` — edit the JSON and run `swift Scripts/generate-presets.swift`.
/// Keeping it generated rather than parsed at launch is what lets this file stay pure: no bundle
/// lookup, no I/O, no decode failure to degrade from.
enum SitePresets {
    /// Skips hosts already covered by an identical matcher, so applying a preset twice — or applying
    /// one that overlaps existing rules — never produces duplicates.
    static func rules(for presets: [SitePreset], targetID: UUID, existing: [Rule], startingOrder: Int) -> [Rule] {
        var covered = Set(existing.map { key($0.match.host, $0.match.hostMode) })
        var created: [Rule] = []
        var order = startingOrder
        for preset in presets {
            for entry in preset.hosts where covered.insert(key(entry.host, entry.mode)).inserted {
                created.append(Rule(
                    name: entry.host,
                    order: order,
                    match: RuleMatch(host: entry.host, hostMode: entry.mode),
                    targetID: targetID
                ))
                order += 1
            }
        }
        return created
    }

    private static func key(_ host: String, _ mode: HostMode) -> String {
        "\(mode.rawValue):\(host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
