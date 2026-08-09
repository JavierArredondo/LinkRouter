import XCTest
@testable import LinkRouter

final class RegexRuleTests: XCTestCase {
    private let target = UUID()
    private func url(_ value: String) throws -> NormalizedURL { try URLNormalizer.normalize(URL(string: value)!).get() }
    private func rule(_ host: String, _ hostMode: HostMode, path: (PathMode, String)? = nil, order: Int = 0) -> Rule {
        Rule(name: host, order: order, match: RuleMatch(host: host, hostMode: hostMode, pathMode: path?.0, pathValue: path?.1), targetID: target)
    }

    func testHostRegexMatchesAlternation() throws {
        let item = rule(#"^(mail|drive)\.google\.com$"#, .regex)
        XCTAssertEqual(RuleEngine().match(try url("https://mail.google.com/u/0"), rules: [item])?.id, item.id)
        XCTAssertEqual(RuleEngine().match(try url("https://drive.google.com"), rules: [item])?.id, item.id)
        XCTAssertNil(RuleEngine().match(try url("https://docs.google.com"), rules: [item]))
    }

    func testHostRegexIsCaseInsensitiveButPreservesPatternCase() throws {
        // Lowercasing the pattern would rewrite `\D` into `\d` and invert its meaning.
        let digits = rule(#"^\D+\.example\.com$"#, .regex)
        XCTAssertEqual(RuleEngine().match(try url("https://abc.example.com"), rules: [digits])?.id, digits.id)
        XCTAssertNil(RuleEngine().match(try url("https://a1.example.com"), rules: [digits]))
        // Hosts normalize to lowercase, so an uppercase pattern still has to match.
        let upper = rule(#"^GITHUB\.com$"#, .regex)
        XCTAssertEqual(RuleEngine().match(try url("https://github.com"), rules: [upper])?.id, upper.id)
    }

    func testPathRegexIsCaseSensitiveLikePrefixAndContains() throws {
        let item = rule("github.com", .exact, path: (.regex, "^/(acme|neuralworks)/"))
        XCTAssertEqual(RuleEngine().match(try url("https://github.com/acme/repo"), rules: [item])?.id, item.id)
        XCTAssertNil(RuleEngine().match(try url("https://github.com/ACME/repo"), rules: [item]))
        XCTAssertNil(RuleEngine().match(try url("https://github.com/other/repo"), rules: [item]))
    }

    func testInvalidPatternMatchesNothingRatherThanEverything() throws {
        let broken = rule("^(unclosed", .regex)
        XCTAssertNil(RuleEngine().match(try url("https://anything.example"), rules: [broken]))
        XCTAssertNotNil(RulePatternValidator.hostError(broken.match))
        XCTAssertFalse(RulePatternValidator.isValid(broken.match))
    }

    func testRegexRanksBetweenExactHostAndWildcard() throws {
        let exact = rule("mail.google.com", .exact, order: 2)
        let pattern = rule(#"^mail\.google\.com$"#, .regex, order: 1)
        let wildcard = rule("*.google.com", .wildcard, order: 0)
        let candidates = [wildcard, pattern, exact]
        XCTAssertEqual(RuleEngine().match(try url("https://mail.google.com"), rules: candidates)?.id, exact.id)
        XCTAssertEqual(RuleEngine().match(try url("https://mail.google.com"), rules: [wildcard, pattern])?.id, pattern.id)
    }

    func testValidatorAcceptsNonRegexModesAndRejectsEmptyPatterns() {
        XCTAssertNil(RulePatternValidator.hostError(RuleMatch(host: "github.com", hostMode: .exact)))
        XCTAssertNotNil(RulePatternValidator.hostError(RuleMatch(host: "  ", hostMode: .regex)))
        XCTAssertNotNil(RulePatternValidator.pathError(RuleMatch(host: "a.com", hostMode: .exact, pathMode: .regex, pathValue: "[")))
    }

    func testMatchingIsBoundedByInputLength() throws {
        let longPath = "https://example.com/" + String(repeating: "a", count: RuleEngine.maximumMatchLength + 500) + "END"
        let item = rule("example.com", .exact, path: (.regex, "END$"))
        // The tail past the cap is not scanned, so this deliberately does not match.
        XCTAssertNil(RuleEngine().match(try url(longPath), rules: [item]))
    }
}

final class SitePresetTests: XCTestCase {
    private let target = UUID()

    func testPresetsGenerateOneRulePerHost() {
        let workspace = SitePresets.all.first { $0.id == "google-workspace" }!
        let rules = SitePresets.rules(for: [workspace], targetID: target, existing: [], startingOrder: 0)
        XCTAssertEqual(rules.count, workspace.hosts.count)
        XCTAssertEqual(rules.map(\.order), Array(0..<workspace.hosts.count))
        XCTAssertTrue(rules.allSatisfy { $0.targetID == target })
    }

    func testApplyingTwiceCreatesNoDuplicates() {
        let presets = SitePresets.all
        let first = SitePresets.rules(for: presets, targetID: target, existing: [], startingOrder: 0)
        let second = SitePresets.rules(for: presets, targetID: target, existing: first, startingOrder: first.count)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
    }

    func testHostsAlreadyCoveredBySameMatcherAreSkipped() {
        let existing = [Rule(name: "gmail", order: 0, match: RuleMatch(host: "MAIL.google.com", hostMode: .exact), targetID: UUID())]
        let workspace = SitePresets.all.first { $0.id == "google-workspace" }!
        let rules = SitePresets.rules(for: [workspace], targetID: target, existing: existing, startingOrder: 0)
        XCTAssertEqual(rules.count, workspace.hosts.count - 1)
        XCTAssertFalse(rules.contains { $0.match.host == "mail.google.com" })
    }

    func testAWildcardEntryDoesNotCollideWithTheSameHostAsExact() {
        let existing = [Rule(name: "slack", order: 0, match: RuleMatch(host: "slack.com", hostMode: .exact), targetID: UUID())]
        let productivity = SitePresets.all.first { $0.id == "productivity-ai" }!
        let rules = SitePresets.rules(for: [productivity], targetID: target, existing: existing, startingOrder: 0)
        XCTAssertTrue(rules.contains { $0.match.host == "*.slack.com" && $0.match.hostMode == .wildcard })
        XCTAssertFalse(rules.contains { $0.match.host == "slack.com" && $0.match.hostMode == .exact })
    }
}

