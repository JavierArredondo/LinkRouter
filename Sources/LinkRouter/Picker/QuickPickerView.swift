import AppKit
import SwiftUI

struct QuickPickerView: View {
    let url: URL
    let sections: [PickerSection]
    let message: String?
    let completion: (Destination?, Bool) -> Void

    @State private var selected = 0
    @State private var remember = false
    @FocusState private var focused: Bool

    private var destinations: [Destination] { PickerLayout.destinations(in: sections) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            if destinations.isEmpty { emptyState } else { list }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(action: handle)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.host() ?? url.absoluteString)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = pathDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sections) { section in
                    if let title = section.title {
                        Text(title.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                    }
                    ForEach(section.entries) { entry in row(entry, isSecondary: section.isSecondary) }
                }
            }
            .padding(6)
        }
        // Capped so a long destination list scrolls instead of growing the panel off-screen.
        .frame(maxHeight: 320)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ entry: PickerEntry, isSecondary: Bool) -> some View {
        let isSelected = entry.index == selected
        return HStack(spacing: 10) {
            shortcutBadge(entry.shortcut, isSelected: isSelected)
            icon(for: entry.destination)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.destination.displayName).lineLimit(1)
                if entry.destination.chromeProfileDirectory != nil {
                    Text("Chrome profile")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.accentColor : .clear))
        .opacity(isSecondary && !isSelected ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { completion(entry.destination, remember) }
        // Hover drives the same selection as the keyboard, so the two never disagree.
        .onHover { if $0 { selected = entry.index } }
    }

    private func shortcutBadge(_ shortcut: Int?, isSelected: Bool) -> some View {
        Text(shortcut.map(String.init) ?? " ")
            .font(.caption.monospacedDigit())
            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            .frame(width: 16)
    }

    private func icon(for destination: Destination) -> some View {
        DestinationIcon(bundleIdentifier: destination.bundleIdentifier, size: 20)
    }

    private var emptyState: some View {
        Label("No available browsers were found.", systemImage: "questionmark.app.dashed")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $remember) {
                Text("Remember \(url.host() ?? "this site")").font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(destinations.isEmpty)
            .keyboardShortcut("r", modifiers: .command)
            HStack(spacing: 14) {
                hint("return", "Open")
                hint("⌘return", "Open & remember")
                hint("esc", "Cancel")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Keyboard

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape { completion(nil, false); return .handled }
        if press.key == .upArrow { move(-1); return .handled }
        if press.key == .downArrow { move(1); return .handled }
        if press.key == .return {
            guard destinations.indices.contains(selected) else { return .handled }
            // ⌘↩ remembers regardless of the toggle: create-a-rule-without-leaving-the-flow in one gesture.
            completion(destinations[selected], remember || press.modifiers.contains(.command))
            return .handled
        }
        if press.modifiers.contains(.command), press.characters.lowercased() == "r" {
            remember.toggle()
            return .handled
        }
        if let digit = Int(press.characters), destinations.indices.contains(digit - 1) {
            selected = digit - 1
            return .handled
        }
        return .ignored
    }

    private func move(_ offset: Int) {
        guard !destinations.isEmpty else { return }
        selected = min(max(0, selected + offset), destinations.count - 1)
    }

    private var pathDetail: String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let detail = path + query
        return detail.isEmpty || detail == "/" ? nil : detail
    }
}
