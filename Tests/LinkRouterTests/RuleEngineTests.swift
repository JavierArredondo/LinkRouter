import XCTest
@testable import LinkRouter

final class RuleEngineTests: XCTestCase {
    private let target = UUID()
    private func url(_ value: String) throws -> NormalizedURL { try URLNormalizer.normalize(URL(string: value)!).get() }
    private func rule(_ host: String, mode: HostMode = .exact, path: (PathMode, String)? = nil, order: Int = 0) -> Rule {
        Rule(name: host, order: order, match: RuleMatch(host: host, hostMode: mode, pathMode: path?.0, pathValue: path?.1), targetID: target)
    }
    func testExactHostIsCaseInsensitive() throws {
        let item = rule("github.com")
        XCTAssertEqual(RuleEngine().match(try url("https://GITHUB.com/a"), rules: [item])?.id, item.id)
    }
    func testWildcardExcludesApexAndIncludesSubdomain() throws { let item = rule("*.google.com", mode: .wildcard); XCTAssertNil(RuleEngine().match(try url("https://google.com"), rules: [item])); XCTAssertEqual(RuleEngine().match(try url("https://docs.google.com"), rules: [item])?.id, item.id) }
    func testExactPathOutranksExactHost() throws { let broad = rule("github.com", order: 0); let narrow = rule("github.com", path: (.prefix, "/company"), order: 1); XCTAssertEqual(RuleEngine().match(try url("https://github.com/company/a"), rules: [broad, narrow])?.id, narrow.id) }
    func testDisabledRuleDoesNotMatch() throws { var item = rule("github.com"); item.enabled = false; XCTAssertNil(RuleEngine().match(try url("https://github.com"), rules: [item])) }
    func testMalformedURLIsRejected() { XCTAssertEqual(URLNormalizer.normalize(URL(string: "https:///missing-host")!), .failure(.malformedURL)) }
    func testRouterAsksWhenTargetIsUnavailable() {
        let destination = Destination(id: target, displayName: "Browser", bundleIdentifier: "com.example.browser")
        let configuration = AppConfiguration(rules: [rule("github.com")], destinations: [destination])
        guard case .ask(_, _, .unavailableDestination(target)) = Router(ownBundleIdentifier: "com.linkrouter.app").decide(URL(string: "https://github.com")!, configuration: configuration, availableBundleIdentifiers: []) else { return XCTFail("Expected recoverable picker decision") }
    }
    private func localState(_ json: String) -> Data { Data(json.utf8) }

    func testChromiumProfilesFollowChromeOrderAndUseDisplayNames() {
        let data = localState("""
        {"profile":{"profiles_order":["Default","Profile 5","Profile 1"],
         "info_cache":{"Profile 1":{"name":"Javier"},"Default":{"name":"neuralworks.cl"},"Profile 5":{"name":"latam.com"}}}}
        """)
        let profiles = ChromiumProfileRegistry.parse(localState: data)
        XCTAssertEqual(profiles.map(\.directoryName), ["Default", "Profile 5", "Profile 1"])
        XCTAssertEqual(profiles.map(\.displayName), ["neuralworks.cl", "latam.com", "Javier"])
    }

    func testChromiumProfilesSkipEphemeralAndFallBackToDirectoryName() {
        let data = localState("""
        {"profile":{"info_cache":{"Guest":{"name":"Guest","is_ephemeral":true},"Profile 2":{"name":"   "}}}}
        """)
        let profiles = ChromiumProfileRegistry.parse(localState: data)
        XCTAssertEqual(profiles.map(\.directoryName), ["Profile 2"])
        XCTAssertEqual(profiles.first?.displayName, "Profile 2")
    }

    func testMalformedLocalStateYieldsNoProfilesInsteadOfFailing() {
        XCTAssertTrue(ChromiumProfileRegistry.parse(localState: localState("{\"profile\":{}}")).isEmpty)
        XCTAssertTrue(ChromiumProfileRegistry.parse(localState: localState("not json")).isEmpty)
    }

    func testChromiumProfilesAreDistinctDestinationsDespiteSharedBundleIdentifier() {
        let chrome = ChromiumProfileRegistry.browsers[0].bundleIdentifier
        let work = Destination(displayName: "Chrome — work", bundleIdentifier: chrome, kind: .chromiumProfile, metadata: [Destination.chromiumProfileDirectoryKey: "Default"])
        let personal = Destination(displayName: "Chrome — personal", bundleIdentifier: chrome, kind: .chromiumProfile, metadata: [Destination.chromiumProfileDirectoryKey: "Profile 1"])
        let plain = Destination(displayName: "Google Chrome", bundleIdentifier: chrome)
        XCTAssertEqual(Set([work.identityKey, personal.identityKey, plain.identityKey]).count, 3)
        XCTAssertEqual(plain.identityKey, chrome)
    }

    func testRouterOpensChromeProfileDestination() {
        let profile = Destination(id: target, displayName: "Chrome — work", bundleIdentifier: ChromiumProfileRegistry.browsers[0].bundleIdentifier, kind: .chromiumProfile, metadata: [Destination.chromiumProfileDirectoryKey: "Profile 1"])
        let configuration = AppConfiguration(rules: [rule("github.com")], destinations: [profile])
        guard case .open(_, let selected, _) = Router(ownBundleIdentifier: "com.linkrouter.app").decide(URL(string: "https://github.com/a")!, configuration: configuration, availableBundleIdentifiers: [ChromiumProfileRegistry.browsers[0].bundleIdentifier]) else { return XCTFail("Expected the profile destination to route") }
        XCTAssertEqual(selected.chromiumProfileDirectory, "Profile 1")
    }

    func testRouterUsesDefaultOnlyWhenPickerIsDisabled() {
        let destination = Destination(id: target, displayName: "Browser", bundleIdentifier: "com.example.browser")
        var configuration = AppConfiguration(defaultDestinationID: target, askWhenNoMatch: false, destinations: [destination])
        guard case .open(_, let selected, nil) = Router(ownBundleIdentifier: "com.linkrouter.app").decide(URL(string: "https://unknown.example")!, configuration: configuration, availableBundleIdentifiers: [destination.bundleIdentifier]) else { return XCTFail("Expected default destination") }
        XCTAssertEqual(selected.id, target)
        configuration.askWhenNoMatch = true
        guard case .ask = Router(ownBundleIdentifier: "com.linkrouter.app").decide(URL(string: "https://unknown.example")!, configuration: configuration, availableBundleIdentifiers: [destination.bundleIdentifier]) else { return XCTFail("Expected picker") }
    }
}
