import XCTest
@testable import LinkRouter

final class RuleSummaryTests: XCTestCase {
    func testDescribesEachHostMode() {
        XCTAssertEqual(RuleSummary.hostLabel(RuleMatch(host: "a.com", hostMode: .exact)), "exact host")
        XCTAssertEqual(RuleSummary.hostLabel(RuleMatch(host: "*.a.com", hostMode: .wildcard)), "subdomains")
        XCTAssertEqual(RuleSummary.hostLabel(RuleMatch(host: "^a\\.com$", hostMode: .regex)), "regex")
    }

    func testDescribesEachPathCondition() {
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact)), "any path")
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .prefix, pathValue: "/acme")), "path starts with /acme")
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .contains, pathValue: "/x/")), "path contains /x/")
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .regex, pathValue: "^/a")), "path matches ^/a")
    }

    func testAPathModeWithNoValueReadsAsAnyPath() {
        // The editor can leave the mode set with an empty field; the engine ignores it, so the
        // summary must not claim a condition that is not applied.
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .prefix, pathValue: "")), "any path")
        XCTAssertEqual(RuleSummary.pathLabel(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .prefix, pathValue: nil)), "any path")
    }

    func testFullDescriptionJoinsHostAndPath() {
        let match = RuleMatch(host: "*.google.com", hostMode: .wildcard, pathMode: .prefix, pathValue: "/a/")
        XCTAssertEqual(RuleSummary.description(match), "subdomains · path starts with /a/")
    }
}
