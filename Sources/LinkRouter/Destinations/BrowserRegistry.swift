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
        return browsers + chromeProfiles(alongside: browsers)
    }

    /// Claiming `https` is not the same as being a browser — chat clients and helpers claim it too.
    /// Handling `public.html` documents is the distinction macOS itself draws for its default-browser
    /// list, and it is reachable through public API rather than by reading other apps' Info.plists.
    private func webDocumentHandlers() -> Set<String> {
        Set(NSWorkspace.shared.urlsForApplications(toOpen: .html).compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    private func chromeProfiles(alongside browsers: [Destination]) -> [Destination] {
        guard browsers.contains(where: { $0.bundleIdentifier == ChromeProfileRegistry.chromeBundleIdentifier }) else { return [] }
        return ChromeProfileRegistry.profiles().map { profile in
            Destination(
                displayName: "Chrome — \(profile.displayName)",
                bundleIdentifier: ChromeProfileRegistry.chromeBundleIdentifier,
                kind: .chromeProfile,
                metadata: [
                    Destination.chromeProfileDirectoryKey: profile.directoryName,
                    Destination.webDocumentHandlerKey: "true"
                ]
            )
        }
    }

    func installedBundleIdentifiers() -> Set<String> {
        Set(discoveredDestinations(excluding: "").map(\.bundleIdentifier))
    }
}
