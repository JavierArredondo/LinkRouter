import XCTest
@testable import LinkRouter

final class RoutePlaygroundTests: XCTestCase {
    private let chrome = Destination(displayName: "Chrome", bundleIdentifier: "com.google.Chrome")
    private let firefox = Destination(displayName: "Firefox", bundleIdentifier: "org.mozilla.firefox")

    private func rule(_ host: String, _ mode: HostMode, to target: Destination, order: Int = 0, path: (PathMode, String)? = nil) -> Rule {
        Rule(name: host, order: order,
             match: RuleMatch(host: host, hostMode: mode, pathMode: path?.0, pathValue: path?.1),
             targetID: target.id)
    }

    private func explain(_ value: String, _ configuration: AppConfiguration) -> RouteExplanation {
        RoutePlayground.explain(
            URL(string: value)!,
            configuration: configuration,
            availableBundleIdentifiers: ["com.google.Chrome", "org.mozilla.firefox"],
            ownBundleIdentifier: "com.linkrouter.app"
        )
    }

    func testReportsNormalisedHostAndPath() {
        let result = explain("https://GitHub.com/Acme/repo", AppConfiguration())
        XCTAssertEqual(result.host, "github.com")
        XCTAssertEqual(result.path, "/Acme/repo")
        XCTAssertNil(result.error)
    }

    func testEveryMatchingRuleIsListedWithTheWinnerMarked() {
        let wildcard = rule("*.google.com", .wildcard, to: firefox, order: 0)
        let exact = rule("mail.google.com", .exact, to: chrome, order: 1)
        let configuration = AppConfiguration(rules: [wildcard, exact], destinations: [chrome, firefox])
        let result = explain("https://mail.google.com/u/0", configuration)

        // Both match; the exact host outranks the wildcard regardless of order.
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertEqual(result.matchedRule?.id, exact.id)
        XCTAssertEqual(result.candidates.first?.rule.id, exact.id, "Candidates are ranked, most specific first")
        XCTAssertEqual(result.destination?.id, chrome.id)
    }

    func testARuleThatDoesNotMatchIsNotListed() {
        let other = rule("example.com", .exact, to: chrome)
        let configuration = AppConfiguration(rules: [other], destinations: [chrome])
        let result = explain("https://github.com", configuration)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertNil(result.matchedRule)
        XCTAssertNil(result.destination, "With no rule and the picker on, there is no destination to report")
    }

    func testDisabledRulesNeverAppearAsCandidates() {
        var disabled = rule("github.com", .exact, to: chrome)
        disabled.enabled = false
        let configuration = AppConfiguration(rules: [disabled], destinations: [chrome])
        XCTAssertTrue(explain("https://github.com", configuration).candidates.isEmpty)
    }

    func testTheDefaultDestinationIsReportedWhenThePickerIsOff() {
        let configuration = AppConfiguration(defaultDestinationID: firefox.id, askWhenNoMatch: false, destinations: [chrome, firefox])
        let result = explain("https://unmatched.example", configuration)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.destination?.id, firefox.id)
    }

    func testStrippedURLIsReportedOnlyWhenItChanges() {
        let configuration = AppConfiguration()
        XCTAssertEqual(explain("https://example.com/a?utm_source=x&id=1", configuration).strippedURL?.absoluteString,
                       "https://example.com/a?id=1")
        XCTAssertNil(explain("https://example.com/a?id=1", configuration).strippedURL,
                     "Nothing to strip must read as nothing to report")
    }

    func testStrippingIsNotReportedWhenTheSettingIsOff() {
        var configuration = AppConfiguration()
        configuration.removeTrackingParameters = false
        XCTAssertNil(explain("https://example.com/a?utm_source=x", configuration).strippedURL)
    }

    func testAMalformedURLReportsTheRouterError() {
        let result = explain("ftp://example.com/file", AppConfiguration())
        XCTAssertEqual(result.error, .unsupportedScheme)
        XCTAssertNil(result.host)
        XCTAssertTrue(result.candidates.isEmpty)
    }
}
