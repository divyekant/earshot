@testable import EarshotCore
import XCTest

/// A page that a plugin wrote never goes to Jev (R-MD-1, D-10). Made-up paths only.
final class PluginPageTests: XCTestCase {
    func testPluginPage() {
        XCTAssertTrue(SafetyPolicy.pluginPage(url: "file:///Users/me/Library/Application%20Support/earshot/plugin-data/pa/today.html"))
        XCTAssertTrue(SafetyPolicy.pluginPage(url: "file:///Users/me/Library/Application%20Support/earshot/plugin-data/pa/pages/../flags.html"))
        XCTAssertFalse(SafetyPolicy.pluginPage(url: "file:///Users/me/Documents/today.html"))
        XCTAssertFalse(SafetyPolicy.pluginPage(url: "https://news.example/earshot/plugin-data/today.html"))
        XCTAssertFalse(SafetyPolicy.pluginPage(url: nil))
    }

    func testNoCloud() {
        let el = ScreenElement(id: "e1", role: "AXLink", label: "today", risky: false)
        func screen(_ url: String?) -> ScreenSnapshot { ScreenSnapshot(bundleID: "com.apple.Safari", windowTitle: "PA", url: url, elements: [el]) }
        XCTAssertEqual(SafetyPolicy.noCloud(screen("file:///Users/me/Library/Application%20Support/earshot/plugin-data/pa/today.html")),
                       "a plugin page")
        XCTAssertNotNil(SafetyPolicy.noCloud(screen("https://news.example/login")))
        XCTAssertNil(SafetyPolicy.noCloud(screen("https://news.example/")))
        XCTAssertNil(SafetyPolicy.noCloud(nil))
    }
}
