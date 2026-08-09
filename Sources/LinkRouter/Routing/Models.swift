import Foundation

enum DestinationKind: String, Codable, CaseIterable, Sendable {
    case browser
    case chromeProfile
    case nativeApp
}

struct Destination: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var bundleIdentifier: String
    var kind: DestinationKind
    var metadata: [String: String]

    init(id: UUID = UUID(), displayName: String, bundleIdentifier: String, kind: DestinationKind = .browser, metadata: [String: String] = [:]) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.kind = kind
        self.metadata = metadata
    }
}

extension Destination {
    static let chromeProfileDirectoryKey = "chromeProfileDirectory"
    static let webDocumentHandlerKey = "handlesWebDocuments"

    var chromeProfileDirectory: String? { metadata[Destination.chromeProfileDirectoryKey] }

    /// Anything that claims `https` shows up as a candidate, including apps that are not browsers.
    /// Absent means "assume browser" so destinations stored before this flag existed are not all
    /// demoted to the secondary section at once.
    var isWebBrowser: Bool { metadata[Destination.webDocumentHandlerKey] != "false" }

    /// Every Chrome profile shares one bundle identifier, so identity has to include the profile
    /// directory — otherwise profiles collapse into a single destination when the list is refreshed.
    var identityKey: String { chromeProfileDirectory.map { "\(bundleIdentifier)#\($0)" } ?? bundleIdentifier }
}

enum HostMode: String, Codable, CaseIterable, Sendable { case exact, wildcard, regex }
enum PathMode: String, Codable, CaseIterable, Sendable { case prefix, contains, regex }

struct RuleMatch: Codable, Equatable, Sendable {
    var host: String
    var hostMode: HostMode
    var pathMode: PathMode?
    var pathValue: String?
}

struct Rule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var enabled: Bool
    var order: Int
    var match: RuleMatch
    var targetID: UUID

    init(id: UUID = UUID(), name: String, enabled: Bool = true, order: Int, match: RuleMatch, targetID: UUID) {
        self.id = id; self.name = name; self.enabled = enabled; self.order = order; self.match = match; self.targetID = targetID
    }
}

struct AppConfiguration: Codable, Sendable {
    var schemaVersion: Int = 1
    var defaultDestinationID: UUID?
    var askWhenNoMatch: Bool = true
    var rules: [Rule] = []
    var destinations: [Destination] = []
    var diagnosticsEnabled: Bool = false
}

struct NormalizedURL: Equatable, Sendable {
    let original: URL
    let scheme: String
    let host: String
    let path: String
}

enum RouteError: Error, Equatable, Sendable {
    case malformedURL
    case unsupportedScheme
    case unavailableDestination(UUID)
    case recursiveDestination
}

enum RouteDecision: Sendable {
    case open(URL, Destination, Rule?)
    case ask(URL, [Destination], RouteError?)
    case reject(URL, RouteError)
}
