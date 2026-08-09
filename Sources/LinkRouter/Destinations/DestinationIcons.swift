import AppKit
import SwiftUI

/// Resolves and caches application icons for destinations.
///
/// Shared by the picker and the settings window: resolving on every render would hit disk on each
/// repaint. The cache is process-lifetime and cleared whenever destinations are rediscovered, so an
/// app that moved or was updated does not keep showing a stale icon.
@MainActor
enum DestinationIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = cache[bundleIdentifier] { return cached }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        cache[bundleIdentifier] = image
        return image
    }

    static func invalidate() { cache.removeAll() }
}

struct DestinationIcon: View {
    let bundleIdentifier: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = DestinationIcons.icon(for: bundleIdentifier) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
