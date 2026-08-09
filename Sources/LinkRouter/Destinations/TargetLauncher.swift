import AppKit

@MainActor
final class TargetLauncher {
    func launch(_ url: URL, in destination: Destination) async -> Error? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: destination.bundleIdentifier) else {
            return RouteError.unavailableDestination(destination.id)
        }
        if let profileDirectory = destination.chromiumProfileDirectory {
            return await launchChromiumProfile(url, profileDirectory: profileDirectory, appURL: appURL)
        }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { _, error in
                continuation.resume(returning: error)
            }
        }
    }

    /// The URL travels as a command-line argument rather than through `open(_:withApplicationAt:)`,
    /// because macOS drops `arguments` for an app that is already running. `createsNewApplicationInstance`
    /// forces a fresh process whose command line the browser's singleton forwards to the live instance —
    /// without it the link lands in whichever profile happens to be frontmost. Verified against Chrome;
    /// the mechanism is common to every Chromium derivative.
    private func launchChromiumProfile(_ url: URL, profileDirectory: String, appURL: URL) async -> Error? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--profile-directory=\(profileDirectory)", url.absoluteString]
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                continuation.resume(returning: error)
            }
        }
    }
}
