import Foundation

struct PickerEntry: Identifiable, Equatable, Sendable {
    let destination: Destination
    /// Position across every section, so selection state is a single flat index.
    let index: Int

    var id: UUID { destination.id }
    var shortcut: Int? { index < PickerLayout.maximumShortcut ? index + 1 : nil }
}

struct PickerSection: Identifiable, Equatable, Sendable {
    let title: String?
    let isSecondary: Bool
    let entries: [PickerEntry]

    var id: String { title ?? "" }
}

/// Ordering and numbering live here, away from AppKit, so they stay covered by tests —
/// the same split the project already uses for `Routing/`.
enum PickerLayout {
    static let maximumShortcut = 9

    static func sections(for destinations: [Destination]) -> [PickerSection] {
        let browsers = destinations.filter(\.isWebBrowser)
        let others = destinations.filter { !$0.isWebBrowser }
        var next = 0
        func entries(_ items: [Destination]) -> [PickerEntry] {
            items.map { destination in
                defer { next += 1 }
                return PickerEntry(destination: destination, index: next)
            }
        }
        // Numbered across sections, so a given digit always means the same row.
        let primary = entries(browsers)
        let secondary = entries(others)
        var sections: [PickerSection] = []
        if !primary.isEmpty {
            // The heading only earns its space when there is a second group to tell it apart from.
            sections.append(PickerSection(title: secondary.isEmpty ? nil : "Browsers", isSecondary: false, entries: primary))
        }
        if !secondary.isEmpty {
            sections.append(PickerSection(title: "Other apps", isSecondary: true, entries: secondary))
        }
        return sections
    }

    static func destinations(in sections: [PickerSection]) -> [Destination] {
        sections.flatMap { $0.entries.map(\.destination) }
    }
}
