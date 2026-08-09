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
enum SitePresets {
    static let all: [SitePreset] = [
        SitePreset(
            id: "google-workspace",
            title: "Google Workspace",
            detail: "Gmail, Calendar, Drive, Docs, Meet, Chat, Groups, Contacts, Admin",
            hosts: [
                PresetHost("mail.google.com"),
                PresetHost("calendar.google.com"),
                PresetHost("drive.google.com"),
                PresetHost("docs.google.com"),
                PresetHost("meet.google.com"),
                PresetHost("chat.google.com"),
                PresetHost("groups.google.com"),
                PresetHost("contacts.google.com"),
                PresetHost("admin.google.com")
            ]
        ),
        SitePreset(
            id: "productivity-ai",
            title: "Productivity & AI",
            detail: "Notion, Linear, Slack, Atlassian, Claude, ChatGPT",
            hosts: [
                PresetHost("notion.so"),
                PresetHost("*.notion.so", .wildcard),
                PresetHost("linear.app"),
                PresetHost("slack.com"),
                PresetHost("*.slack.com", .wildcard),
                PresetHost("*.atlassian.net", .wildcard),
                PresetHost("claude.ai"),
                PresetHost("chatgpt.com")
            ]
        )
    ]

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
