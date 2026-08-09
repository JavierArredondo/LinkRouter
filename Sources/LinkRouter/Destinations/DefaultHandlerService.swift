import AppKit

@MainActor
final class DefaultHandlerService {
    func setLinkRouterAsDefault() async throws {
        let applicationURL = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: "http")
        try await NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: "https")
    }

    func currentStatus(ownBundleIdentifier: String) -> String {
        let http = handlerIdentifier(for: "http://example.com")
        let https = handlerIdentifier(for: "https://example.com")
        if http == ownBundleIdentifier && https == ownBundleIdentifier { return "LinkRouter handles http and https" }
        if http == ownBundleIdentifier || https == ownBundleIdentifier { return "LinkRouter handles only one web scheme — repair needed" }
        return "LinkRouter is not the default web handler"
    }

    func isDefaultForWeb(ownBundleIdentifier: String) -> Bool {
        handlerIdentifier(for: "http://example.com") == ownBundleIdentifier
            && handlerIdentifier(for: "https://example.com") == ownBundleIdentifier
    }

    private func handlerIdentifier(for rawURL: String) -> String? {
        guard let url = URL(string: rawURL), let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: handler)?.bundleIdentifier
    }
}
