import Foundation

struct ChromeProfile: Equatable, Sendable {
    let directoryName: String
    let displayName: String
}

/// Reads Chrome's profile list from its on-disk `Local State`.
///
/// This is an undocumented Chrome internal, so every failure here is non-fatal: a missing, renamed,
/// or restructured file yields an empty list, which degrades routing to the plain "Google Chrome"
/// destination instead of breaking it.
enum ChromeProfileRegistry {
    static let chromeBundleIdentifier = "com.google.Chrome"

    static func userDataDirectory(_ fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
    }

    static func profiles(fileManager: FileManager = .default) -> [ChromeProfile] {
        let stateURL = userDataDirectory(fileManager).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: stateURL) else { return [] }
        return parse(localState: data)
    }

    /// Pure, so the fragile part — Chrome's undocumented format — stays covered by tests.
    static func parse(localState data: Data) -> [ChromeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        // `profiles_order` is what Chrome's own UI shows; anything missing from it sorts last but stays listed.
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
            return ChromeProfile(directoryName: directory, displayName: name.isEmpty ? directory : name)
        }
    }
}
