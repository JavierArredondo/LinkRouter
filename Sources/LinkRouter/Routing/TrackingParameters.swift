import Foundation

/// Strips tracking parameters from a link before it is opened.
///
/// The lists live in `TrackingParameters+Generated.swift`, generated from
/// `Presets/tracking-parameters.json`. Only the matching logic is here, so it stays pure and tested.
enum TrackingParameters {
    static func strip(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems,
              !items.isEmpty else { return url }
        let host = components.host?.lowercased() ?? ""
        let kept = items.filter { !isTracking($0.name, host: host) }
        // Returning the original when nothing matched keeps this a genuine no-op: rebuilding the URL
        // can re-encode characters and hand the browser something subtly different.
        guard kept.count != items.count else { return url }
        // An empty array would still leave a trailing "?"; nil removes the query entirely.
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    static func isTracking(_ name: String, host: String) -> Bool {
        let parameter = name.lowercased()
        if globalNames.contains(parameter) { return true }
        if globalPrefixes.contains(where: { parameter.hasPrefix($0) }) { return true }
        return hostScopedNames.contains { entry in
            matches(host: host, scope: entry.key) && entry.value.contains(parameter)
        }
    }

    /// A scope covers its own host and any subdomain, so a rule written for `youtube.com` also
    /// applies to `www.youtube.com` and `m.youtube.com`.
    private static func matches(host: String, scope: String) -> Bool {
        host == scope || host.hasSuffix("." + scope)
    }
}
