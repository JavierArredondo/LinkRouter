import XCTest
@testable import LinkRouter

final class PickerLayoutTests: XCTestCase {
    private func destination(_ name: String, isBrowser: Bool) -> Destination {
        Destination(displayName: name, bundleIdentifier: "com.example.\(name)", metadata: [Destination.webDocumentHandlerKey: isBrowser ? "true" : "false"])
    }

    func testBrowsersComeFirstAndNonBrowsersAreASecondarySection() {
        let sections = PickerLayout.sections(for: [
            destination("Chat", isBrowser: false),
            destination("Firefox", isBrowser: true),
            destination("Safari", isBrowser: true)
        ])
        XCTAssertEqual(sections.map(\.title), ["Browsers", "Other apps"])
        XCTAssertEqual(sections.map(\.isSecondary), [false, true])
        XCTAssertEqual(PickerLayout.destinations(in: sections).map(\.displayName), ["Firefox", "Safari", "Chat"])
    }

    func testNumberingRunsContinuouslyAcrossSections() {
        let sections = PickerLayout.sections(for: [
            destination("Firefox", isBrowser: true),
            destination("Chat", isBrowser: false)
        ])
        XCTAssertEqual(sections.flatMap(\.entries).map(\.index), [0, 1])
        XCTAssertEqual(sections.flatMap(\.entries).map(\.shortcut), [1, 2])
    }

    func testShortcutsStopAtNineButRowsRemain() {
        let many = (1...11).map { destination("Browser\($0)", isBrowser: true) }
        let entries = PickerLayout.sections(for: many).flatMap(\.entries)
        XCTAssertEqual(entries.count, 11)
        XCTAssertEqual(entries.last?.shortcut, nil)
        XCTAssertEqual(entries[PickerLayout.maximumShortcut - 1].shortcut, 9)
        XCTAssertNil(entries[PickerLayout.maximumShortcut].shortcut)
    }

    func testHeadingIsOmittedWhenThereIsNothingToDistinguish() {
        let sections = PickerLayout.sections(for: [destination("Firefox", isBrowser: true)])
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
    }

    func testDestinationsStoredBeforeTheFlagExistedCountAsBrowsers() {
        let legacy = Destination(displayName: "Firefox", bundleIdentifier: "org.mozilla.firefox")
        XCTAssertTrue(legacy.isWebBrowser)
        let sections = PickerLayout.sections(for: [legacy])
        XCTAssertEqual(sections.count, 1)
        XCTAssertFalse(sections[0].isSecondary)
    }

    func testEmptyInputProducesNoSections() {
        XCTAssertTrue(PickerLayout.sections(for: []).isEmpty)
    }
}

final class NativeAppDestinationTests: XCTestCase {
    func testAHandPickedAppRanksWithTheBrowsersNotBelowThem() {
        // It was chosen deliberately; only apps that merely happen to claim https get demoted.
        let zoom = Destination(displayName: "Zoom", bundleIdentifier: "us.zoom.xos", kind: .nativeApp,
                               metadata: [Destination.webDocumentHandlerKey: "false"])
        let chat = Destination(displayName: "Chat", bundleIdentifier: "com.example.chat",
                               metadata: [Destination.webDocumentHandlerKey: "false"])
        let firefox = Destination(displayName: "Firefox", bundleIdentifier: "org.mozilla.firefox")

        XCTAssertTrue(zoom.isPrimaryDestination)
        XCTAssertFalse(chat.isPrimaryDestination)

        let sections = PickerLayout.sections(for: [chat, firefox, zoom])
        XCTAssertEqual(sections.map(\.title), ["Browsers", "Other apps"])
        XCTAssertEqual(sections[0].entries.map(\.destination.displayName), ["Firefox", "Zoom"])
        XCTAssertEqual(sections[1].entries.map(\.destination.displayName), ["Chat"])
    }

    func testANativeAppDestinationRoutesLikeAnyOther() throws {
        let zoom = Destination(displayName: "Zoom", bundleIdentifier: "us.zoom.xos", kind: .nativeApp)
        let rule = Rule(name: "zoom", order: 0, match: RuleMatch(host: "zoom.us", hostMode: .exact), targetID: zoom.id)
        let configuration = AppConfiguration(rules: [rule], destinations: [zoom])
        guard case .open(_, let selected, _) = Router(ownBundleIdentifier: "com.linkrouter.app")
            .decide(URL(string: "https://zoom.us/j/123")!, configuration: configuration, availableBundleIdentifiers: ["us.zoom.xos"])
        else { return XCTFail("Expected the native app to be routable") }
        XCTAssertEqual(selected.kind, .nativeApp)
    }

    func testAnUninstalledNativeAppDegradesToThePicker() {
        let zoom = Destination(displayName: "Zoom", bundleIdentifier: "us.zoom.xos", kind: .nativeApp)
        let rule = Rule(name: "zoom", order: 0, match: RuleMatch(host: "zoom.us", hostMode: .exact), targetID: zoom.id)
        let configuration = AppConfiguration(rules: [rule], destinations: [zoom])
        guard case .ask = Router(ownBundleIdentifier: "com.linkrouter.app")
            .decide(URL(string: "https://zoom.us/j/123")!, configuration: configuration, availableBundleIdentifiers: [])
        else { return XCTFail("A missing app must degrade, not drop the link") }
    }
}
