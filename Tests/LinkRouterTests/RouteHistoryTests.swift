import XCTest
@testable import LinkRouter

final class RouteHistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_770_000_000)

    private func entry(
        _ host: String,
        path: String = "",
        outcome: HistoryOutcome = .picker,
        rule: String? = nil,
        offset: TimeInterval = 0
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            date: epoch.addingTimeInterval(offset),
            host: host,
            path: path,
            outcome: outcome,
            destinationName: "Firefox",
            destinationBundleIdentifier: "org.mozilla.firefox",
            ruleName: rule
        )
    }

    // MARK: - Recording

    func testQueryStringsAreNeverRecorded() {
        let url = URL(string: "https://support.claude.com/articles/15424964?utm_source=email&session=abc123")!
        let made = HistoryEntry.make(url: url, date: epoch, outcome: .picker, destination: nil, ruleName: nil)
        XCTAssertEqual(made.host, "support.claude.com")
        XCTAssertEqual(made.path, "/articles/15424964")
        XCTAssertFalse(made.display.contains("session"))
        XCTAssertFalse(made.display.contains("utm_source"))
    }

    func testHostIsLowercasedAndDisplayOmitsAnEmptyPath() {
        let made = HistoryEntry.make(url: URL(string: "https://GitHub.com")!, date: epoch, outcome: .rule, destination: nil, ruleName: "gh")
        XCTAssertEqual(made.host, "github.com")
        XCTAssertEqual(made.display, "github.com")
    }

    func testDestinationDetailsAreCaptured() {
        let destination = Destination(displayName: "Chrome — work", bundleIdentifier: "com.google.Chrome", kind: .chromeProfile)
        let made = HistoryEntry.make(url: URL(string: "https://a.com/x")!, date: epoch, outcome: .rule, destination: destination, ruleName: "acme")
        XCTAssertEqual(made.destinationName, "Chrome — work")
        XCTAssertEqual(made.destinationBundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(made.ruleName, "acme")
    }

    // MARK: - On-disk format

    func testEntriesRoundTripThroughTheLogFormat() throws {
        let original = entry("github.com", path: "/anthropics", outcome: .rule, rule: "gh")
        let line = try XCTUnwrap(RouteHistoryLog.line(for: original))
        XCTAssertTrue(line.hasSuffix("\n"), "One entry per line is what makes appending cheap")
        let decoded = RouteHistoryLog.entries(in: line)
        XCTAssertEqual(decoded, [original])
    }

    func testATruncatedLineDoesNotDiscardTheRestOfTheHistory() throws {
        let good = try XCTUnwrap(RouteHistoryLog.line(for: entry("a.com")))
        let text = good + "{\"id\":\"truncated\",\n" + good
        // An interrupted write must cost one entry, not the whole file.
        XCTAssertEqual(RouteHistoryLog.entries(in: text).count, 2)
    }

    func testTrimmingKeepsTheMostRecentEntries() {
        let entries = (0..<20).map { entry("h\($0).com", offset: TimeInterval($0)) }
        let kept = RouteHistoryLog.trimmed(entries, limit: 5)
        XCTAssertEqual(kept.count, 5)
        XCTAssertEqual(kept.map(\.host), ["h15.com", "h16.com", "h17.com", "h18.com", "h19.com"])
    }

    func testTrimmingLeavesAShortLogUntouched() {
        let entries = [entry("a.com"), entry("b.com")]
        XCTAssertEqual(RouteHistoryLog.trimmed(entries, limit: 500), entries)
    }

    // MARK: - Suggestions

    func testOnlyUnroutedOutcomesBecomeSuggestions() {
        let entries = [
            entry("news.com", outcome: .picker),
            entry("news.com", outcome: .picker),
            entry("blog.com", outcome: .fallback),
            entry("github.com", outcome: .rule, rule: "gh"),   // already handled
            entry("bad.com", outcome: .rejected),
            entry("gone.com", outcome: .cancelled)
        ]
        let suggestions = RouteHistoryLog.suggestions(from: entries, rules: [], limit: 8)
        XCTAssertEqual(suggestions.map(\.host), ["news.com", "blog.com"])
        XCTAssertEqual(suggestions.first?.count, 2)
    }

    func testHostsWithAnExactRuleAreExcluded() {
        let entries = [entry("news.com"), entry("blog.com")]
        let rules = [Rule(name: "n", order: 0, match: RuleMatch(host: "NEWS.com", hostMode: .exact), targetID: UUID())]
        XCTAssertEqual(RouteHistoryLog.suggestions(from: entries, rules: rules, limit: 8).map(\.host), ["blog.com"])
    }

    func testWildcardRulesDoNotSuppressSuggestions() {
        // Judging wildcard coverage would mean running the engine; a redundant suggestion is the
        // cheaper mistake than a missing one.
        let entries = [entry("docs.example.com")]
        let rules = [Rule(name: "w", order: 0, match: RuleMatch(host: "*.example.com", hostMode: .wildcard), targetID: UUID())]
        XCTAssertEqual(RouteHistoryLog.suggestions(from: entries, rules: rules, limit: 8).map(\.host), ["docs.example.com"])
    }

    func testSuggestionsRankByFrequencyThenAlphabetically() {
        let entries = [entry("b.com"), entry("a.com"), entry("a.com"), entry("c.com")]
        let ranked = RouteHistoryLog.suggestions(from: entries, rules: [], limit: 8)
        XCTAssertEqual(ranked.map(\.host), ["a.com", "b.com", "c.com"])
    }

    func testLimitIsRespected() {
        let entries = [entry("a.com"), entry("a.com"), entry("b.com"), entry("c.com")]
        XCTAssertEqual(RouteHistoryLog.suggestions(from: entries, rules: [], limit: 1).map(\.host), ["a.com"])
    }

    // MARK: - Configuration

    func testHistoryDefaultsToOnAndSurvivesConfigurationsWrittenBeforeItExisted() throws {
        XCTAssertTrue(AppConfiguration().isHistoryEnabled)
        let legacy = Data(#"{"schemaVersion":1,"askWhenNoMatch":true,"rules":[],"destinations":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacy)
        XCTAssertTrue(decoded.isHistoryEnabled, "An older config must decode, not be treated as corrupt")
        var off = AppConfiguration()
        off.historyEnabled = false
        XCTAssertFalse(off.isHistoryEnabled)
    }
}
