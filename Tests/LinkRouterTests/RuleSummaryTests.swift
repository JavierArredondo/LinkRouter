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

final class SourceAppRuleTests: XCTestCase {
    private let target = UUID()
    private func url(_ value: String) throws -> NormalizedURL { try URLNormalizer.normalize(URL(string: value)!).get() }
    private func rule(_ host: String, source: String? = nil, path: (PathMode, String)? = nil, order: Int = 0) -> Rule {
        Rule(name: host, order: order,
             match: RuleMatch(host: host, hostMode: .exact, pathMode: path?.0, pathValue: path?.1, sourceBundleIdentifier: source),
             targetID: target)
    }
    private let slack = RouteContext(sourceBundleIdentifier: "com.tinyspeck.slackmacgap")

    func testASourceScopedRuleMatchesOnlyThatSource() throws {
        let scoped = rule("github.com", source: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(RuleEngine().match(try url("https://github.com/a"), rules: [scoped], context: slack)?.id, scoped.id)
        XCTAssertNil(RuleEngine().match(try url("https://github.com/a"), rules: [scoped],
                                        context: RouteContext(sourceBundleIdentifier: "com.apple.mail")))
    }

    func testAnUnknownSourceNeverSatisfiesASourceScopedRule() throws {
        // Otherwise a rule meant for one app quietly becomes a rule for every link.
        let scoped = rule("github.com", source: "com.tinyspeck.slackmacgap")
        XCTAssertNil(RuleEngine().match(try url("https://github.com/a"), rules: [scoped], context: .unknown))
    }

    func testRulesWithoutASourceStillMatchRegardlessOfContext() throws {
        let open = rule("github.com")
        XCTAssertEqual(RuleEngine().match(try url("https://github.com"), rules: [open], context: slack)?.id, open.id)
        XCTAssertEqual(RuleEngine().match(try url("https://github.com"), rules: [open], context: .unknown)?.id, open.id)
    }

    func testASourceConditionOutranksTheSameRuleWithoutOne() throws {
        let general = rule("github.com", order: 0)
        let scoped = rule("github.com", source: "com.tinyspeck.slackmacgap", order: 1)
        XCTAssertEqual(RuleEngine().match(try url("https://github.com"), rules: [general, scoped], context: slack)?.id,
                       scoped.id, "An extra condition is narrower, regardless of list order")
    }

    func testSourceAndPathConditionsWeighTheSameSoOrderDecides() throws {
        // Neither is objectively narrower, so the tie must fall back to the user's ordering — which
        // is `Rule.order`, not the position in the array handed to the engine.
        let pathFirst = rule("github.com", path: (.prefix, "/acme"), order: 0)
        let sourceSecond = rule("github.com", source: "com.tinyspeck.slackmacgap", order: 1)
        XCTAssertEqual(RuleEngine().match(try url("https://github.com/acme/x"), rules: [pathFirst, sourceSecond], context: slack)?.id,
                       pathFirst.id)

        let sourceFirst = rule("github.com", source: "com.tinyspeck.slackmacgap", order: 0)
        let pathSecond = rule("github.com", path: (.prefix, "/acme"), order: 1)
        XCTAssertEqual(RuleEngine().match(try url("https://github.com/acme/x"), rules: [pathSecond, sourceFirst], context: slack)?.id,
                       sourceFirst.id, "Ranking follows Rule.order, so array position must not matter")
    }

    func testMatchingIsCaseInsensitiveOnTheIdentifier() throws {
        let scoped = rule("github.com", source: "COM.Tinyspeck.SlackMacGap")
        XCTAssertEqual(RuleEngine().match(try url("https://github.com"), rules: [scoped], context: slack)?.id, scoped.id)
    }

    func testRulesWrittenBeforeSourcesExistedStillDecode() throws {
        let legacy = Data(#"{"host":"github.com","hostMode":"exact"}"#.utf8)
        let decoded = try JSONDecoder().decode(RuleMatch.self, from: legacy)
        XCTAssertNil(decoded.sourceBundleIdentifier)
        XCTAssertEqual(decoded.host, "github.com")
    }

    func testTheSummaryNamesTheSource() {
        let match = RuleMatch(host: "github.com", hostMode: .exact, sourceBundleIdentifier: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(RuleSummary.description(match), "exact host · any path · from slackmacgap")
        XCTAssertNil(RuleSummary.sourceLabel(RuleMatch(host: "a.com", hostMode: .exact)))
    }
}
