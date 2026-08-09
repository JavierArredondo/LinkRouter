import Foundation

struct ChromiumBrowser: Equatable, Sendable {
    let bundleIdentifier: String
    /// Short label used to build destination names, e.g. "Edge — Work".
    let displayName: String
    /// Location of the browser's user-data directory, relative to Application Support.
    let userDataPath: String
}

struct ChromiumProfile: Equatable, Sendable {
    let directoryName: String
    let displayName: String
}

/// Reads profile lists from the on-disk state of Chromium-family browsers.
///
/// Every Chromium derivative keeps the same `Local State` layout and accepts the same
/// `--profile-directory` argument, so one registry and one launch path cover the whole family;
/// only the bundle identifier and the user-data directory differ.
///
/// This is an undocumented internal of each browser, so every failure here is non-fatal: a missing,
/// renamed, or restructured file yields an empty list, which degrades routing to the plain browser
/// destination instead of breaking it.
enum ChromiumProfileRegistry {
    /// Only browsers actually installed are consulted, so an unused entry costs nothing.
    static let browsers: [ChromiumBrowser] = [
        ChromiumBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Chrome", userDataPath: "Google/Chrome"),
        ChromiumBrowser(bundleIdentifier: "com.google.Chrome.beta", displayName: "Chrome Beta", userDataPath: "Google/Chrome Beta"),
        ChromiumBrowser(bundleIdentifier: "com.google.Chrome.canary", displayName: "Chrome Canary", userDataPath: "Google/Chrome Canary"),
        ChromiumBrowser(bundleIdentifier: "com.microsoft.edgemac", displayName: "Edge", userDataPath: "Microsoft Edge"),
        ChromiumBrowser(bundleIdentifier: "com.brave.Browser", displayName: "Brave", userDataPath: "BraveSoftware/Brave-Browser"),
        ChromiumBrowser(bundleIdentifier: "com.brave.Browser.beta", displayName: "Brave Beta", userDataPath: "BraveSoftware/Brave-Browser-Beta"),
        ChromiumBrowser(bundleIdentifier: "com.vivaldi.Vivaldi", displayName: "Vivaldi", userDataPath: "Vivaldi"),
        ChromiumBrowser(bundleIdentifier: "org.chromium.Chromium", displayName: "Chromium", userDataPath: "Chromium")
    ]

    static func browser(withBundleIdentifier identifier: String) -> ChromiumBrowser? {
        browsers.first { $0.bundleIdentifier == identifier }
    }

    static func userDataDirectory(for browser: ChromiumBrowser, _ fileManager: FileManager = .default) -> URL {
        browser.userDataPath.split(separator: "/").reduce(
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    static func profiles(for browser: ChromiumBrowser, fileManager: FileManager = .default) -> [ChromiumProfile] {
        let stateURL = userDataDirectory(for: browser, fileManager).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: stateURL) else { return [] }
        return parse(localState: data)
    }

    /// Pure, so the fragile part — an undocumented on-disk format — stays covered by tests.
    static func parse(localState data: Data) -> [ChromiumProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        // `profiles_order` is what the browser's own UI shows; anything missing from it sorts last
        // but stays listed.
        let order = profile["profiles_order"] as? [String] ?? []
        let ordered = cache.keys.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs) ?? Int.max
            let right = order.firstIndex(of: rhs) ?? Int.max
            return left == right ? lhs < rhs : left < right
        }
        return ordered.compactMap { directory in
            guard let entry = cache[directory] as? [String: Any] else { return nil }
            guard entry["is_ephemeral"] as? Bool != true else { return nil }
            let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ChromiumProfile(directoryName: directory, displayName: name.isEmpty ? directory : name)
        }
    }
}
