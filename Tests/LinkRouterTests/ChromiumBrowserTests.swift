import XCTest
@testable import LinkRouter

final class ChromiumBrowserTests: XCTestCase {
    func testBrowserTableIsUnambiguous() {
        let identifiers = ChromiumProfileRegistry.browsers.map(\.bundleIdentifier)
        let paths = ChromiumProfileRegistry.browsers.map(\.userDataPath)
        // A duplicate identifier would make lookup order-dependent; a duplicate path would attribute
        // one browser's profiles to another.
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertFalse(ChromiumProfileRegistry.browsers.contains { $0.displayName.isEmpty })
    }

    func testChromeIsStillRecognisedByIdentifier() {
        let chrome = ChromiumProfileRegistry.browser(withBundleIdentifier: "com.google.Chrome")
        XCTAssertEqual(chrome?.displayName, "Chrome")
        XCTAssertEqual(chrome?.userDataPath, "Google/Chrome")
        XCTAssertNil(ChromiumProfileRegistry.browser(withBundleIdentifier: "org.mozilla.firefox"))
    }

    func testNestedUserDataPathsResolveToNestedDirectories() {
        // Brave nests its user data one level deeper; a path joined as a single component would point
        // at a directory that does not exist and silently yield no profiles.
        let brave = try! XCTUnwrap(ChromiumProfileRegistry.browser(withBundleIdentifier: "com.brave.Browser"))
        let url = ChromiumProfileRegistry.userDataDirectory(for: brave)
        XCTAssertEqual(url.lastPathComponent, "Brave-Browser")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "BraveSoftware")
    }

    func testEveryBrowserParsesTheSameLocalStateFormat() {
        // One parser serves the whole family; this guards the assumption that the format is shared.
        let data = Data(#"{"profile":{"profiles_order":["Default"],"info_cache":{"Default":{"name":"Work"}}}}"#.utf8)
        let profiles = ChromiumProfileRegistry.parse(localState: data)
        XCTAssertEqual(profiles, [ChromiumProfile(directoryName: "Default", displayName: "Work")])
    }

    func testStoredConfigurationsFromBeforeTheRenameStillDecode() throws {
        // The kind and metadata key kept their original spelling on purpose: changing them would make
        // ConfigurationStore treat an existing configuration.json as corrupt and archive it.
        let json = Data("""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","displayName":"Chrome — Javier",
         "bundleIdentifier":"com.google.Chrome","kind":"chromeProfile",
         "metadata":{"chromeProfileDirectory":"Profile 1"}}
        """.utf8)
        let decoded = try JSONDecoder().decode(Destination.self, from: json)
        XCTAssertEqual(decoded.kind, .chromiumProfile)
        XCTAssertEqual(decoded.chromiumProfileDirectory, "Profile 1")
        XCTAssertEqual(decoded.identityKey, "com.google.Chrome#Profile 1")
    }
}
