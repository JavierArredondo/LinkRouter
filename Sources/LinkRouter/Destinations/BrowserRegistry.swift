import AppKit
import UniformTypeIdentifiers

@MainActor
final class BrowserRegistry {
    func discoveredDestinations(excluding ownBundleIdentifier: String) -> [Destination] {
        let urls = ["https://example.com", "http://example.com"].compactMap(URL.init(string:)).flatMap {
            NSWorkspace.shared.urlsForApplications(toOpen: $0)
        }
        let webDocumentHandlers = self.webDocumentHandlers()
        var seen = Set<String>()
        // Sorted because `Set` iteration order is not stable, and an unstable list would reshuffle
        // the picker's number shortcuts between launches.
        let browsers = Array(Set(urls)).compactMap { appURL -> Destination? in
            guard let id = Bundle(url: appURL)?.bundleIdentifier, id != ownBundleIdentifier else { return nil }
            guard seen.insert(id).inserted else { return nil } // The same app can be registered from two paths.
            return Destination(
                displayName: FileManager.default.displayName(atPath: appURL.path),
                bundleIdentifier: id,
                metadata: [Destination.webDocumentHandlerKey: webDocumentHandlers.contains(id) ? "true" : "false"]
            )
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return browsers + chromiumProfiles(alongside: browsers)
    }

    /// Claiming `https` is not the same as being a browser — chat clients and helpers claim it too.
    /// Handling `public.html` documents is the distinction macOS itself draws for its default-browser
    /// list, and it is reachable through public API rather than by reading other apps' Info.plists.
    private func webDocumentHandlers() -> Set<String> {
        Set(NSWorkspace.shared.urlsForApplications(toOpen: .html).compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    /// Expands every installed Chromium-family browser into one destination per profile. Browsers
    /// that are not installed are skipped, and one whose profile list cannot be read simply
    /// contributes nothing — its plain destination still routes.
    private func chromiumProfiles(alongside browsers: [Destination]) -> [Destination] {
        let installed = Set(browsers.map(\.bundleIdentifier))
        return ChromiumProfileRegistry.browsers
            .filter { installed.contains($0.bundleIdentifier) }
            .flatMap { browser in
                ChromiumProfileRegistry.profiles(for: browser).map { profile in
                    Destination(
                        displayName: "\(browser.displayName) — \(profile.displayName)",
                        bundleIdentifier: browser.bundleIdentifier,
                        kind: .chromiumProfile,
                        metadata: [
                            Destination.chromiumProfileDirectoryKey: profile.directoryName,
                            Destination.webDocumentHandlerKey: "true"
                        ]
                    )
                }
            }
    }

    func installedBundleIdentifiers() -> Set<String> {
        Set(discoveredDestinations(excluding: "").map(\.bundleIdentifier))
    }
}
