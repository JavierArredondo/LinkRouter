import XCTest
@testable import LinkRouter

final class TrackingParameterTests: XCTestCase {
    private func strip(_ value: String) -> String {
        TrackingParameters.strip(from: URL(string: value)!).absoluteString
    }

    // MARK: - Stripping

    func testRemovesGlobalNamesAndPrefixedFamilies() {
        XCTAssertEqual(
            strip("https://example.com/a?utm_source=news&utm_campaign=x&fbclid=abc&id=42"),
            "https://example.com/a?id=42"
        )
    }

    func testRemovesTheQuestionMarkWhenNothingSurvives() {
        // An empty query would otherwise leave a bare "?" on the end of every cleaned link.
        XCTAssertEqual(strip("https://example.com/a?utm_source=news"), "https://example.com/a")
    }

    func testKeepsParameterOrderAndOriginalEncoding() {
        let cleaned = strip("https://example.com/s?q=caf%C3%A9%20bar&utm_medium=email&page=2")
        XCTAssertEqual(cleaned, "https://example.com/s?q=caf%C3%A9%20bar&page=2")
    }

    func testAURLWithNothingToStripIsReturnedUnchanged() {
        // Not merely equal — rebuilding can re-encode and hand the browser a subtly different URL.
        let original = URL(string: "https://example.com/a?q=1&b=%2F")!
        XCTAssertEqual(TrackingParameters.strip(from: original), original)
        XCTAssertEqual(TrackingParameters.strip(from: URL(string: "https://example.com/a")!).absoluteString,
                       "https://example.com/a")
    }

    func testFragmentAndPathSurvive() {
        XCTAssertEqual(
            strip("https://example.com/docs/page?utm_source=x&v=2#section-3"),
            "https://example.com/docs/page?v=2#section-3"
        )
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(strip("https://example.com/?UTM_SOURCE=x&FBCLID=y&keep=1"), "https://example.com/?keep=1")
    }

    func testValuelessParametersAreHandled() {
        XCTAssertEqual(strip("https://example.com/?utm_source&flag"), "https://example.com/?flag")
    }

    // MARK: - Host scoping

    func testHostScopedNamesOnlyApplyToTheirHost() {
        // 's' is a share token on x.com and a search query nearly everywhere else; stripping it
        // globally would quietly break searches.
        XCTAssertEqual(strip("https://x.com/user/status/1?s=20&t=abc"), "https://x.com/user/status/1")
        XCTAssertEqual(strip("https://example.com/search?s=20"), "https://example.com/search?s=20")
    }

    func testHostScopesCoverSubdomains() {
        XCTAssertEqual(strip("https://www.youtube.com/watch?v=abc&si=xyz"), "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(strip("https://youtu.be/abc?si=xyz&t=42"), "https://youtu.be/abc?t=42")
    }

    func testAHostScopedNameIsNotStrippedOnALookalikeHost() {
        // Suffix matching must not treat "notyoutube.com" as a subdomain of "youtube.com".
        XCTAssertEqual(strip("https://notyoutube.com/watch?si=xyz"), "https://notyoutube.com/watch?si=xyz")
    }

    func testYouTubeTimestampSurvives() {
        // 't' is scoped to x.com precisely so it keeps working as a YouTube timestamp.
        XCTAssertEqual(strip("https://www.youtube.com/watch?v=abc&t=90"), "https://www.youtube.com/watch?v=abc&t=90")
    }

    // MARK: - Catalog

    func testCatalogIsLowercasedAndNonEmpty() {
        XCTAssertFalse(TrackingParameters.globalNames.isEmpty)
        XCTAssertFalse(TrackingParameters.globalPrefixes.isEmpty)
        XCTAssertTrue(TrackingParameters.globalNames.allSatisfy { $0 == $0.lowercased() })
        XCTAssertTrue(TrackingParameters.globalPrefixes.allSatisfy { $0 == $0.lowercased() })
        XCTAssertTrue(TrackingParameters.hostScopedNames.keys.allSatisfy { $0 == $0.lowercased() })
    }

    func testIsTrackingAgreesWithStripping() {
        XCTAssertTrue(TrackingParameters.isTracking("utm_content", host: "example.com"))
        XCTAssertTrue(TrackingParameters.isTracking("gclid", host: "example.com"))
        XCTAssertFalse(TrackingParameters.isTracking("q", host: "example.com"))
        XCTAssertTrue(TrackingParameters.isTracking("si", host: "music.youtube.com"))
        XCTAssertFalse(TrackingParameters.isTracking("si", host: "example.com"))
    }

    // MARK: - Configuration

    func testRemovalDefaultsToOnAndSurvivesOlderConfigurations() throws {
        XCTAssertTrue(AppConfiguration().isTrackingRemovalEnabled)
        let legacy = Data(#"{"schemaVersion":1,"askWhenNoMatch":true,"rules":[],"destinations":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacy)
        XCTAssertTrue(decoded.isTrackingRemovalEnabled, "An older config must decode, not be treated as corrupt")
        var off = AppConfiguration()
        off.removeTrackingParameters = false
        XCTAssertFalse(off.isTrackingRemovalEnabled)
    }
}
