import EarshotCore
@testable import EarshotRouter
import XCTest

final class WebAddressTests: XCTestCase {
    func testOpenDomain() {
        XCTAssertEqual(WebAddress.parse("open hn.com"), "https://hn.com")
        XCTAssertEqual(WebAddress.parse("Open news.ycombinator.com."), "https://news.ycombinator.com")
        XCTAssertEqual(WebAddress.parse("go to news dot ycombinator dot com"), "https://news.ycombinator.com")
        XCTAssertEqual(WebAddress.parse("visit example.org slash docs"), "https://example.org/docs")
        XCTAssertEqual(WebAddress.parse("please open github.com"), "https://github.com")
        XCTAssertEqual(WebAddress.parse("open http://example.com"), "http://example.com")
    }

    func testGluedCommandWord() {
        // First live test: speech gave "Openhnm.com".
        XCTAssertEqual(WebAddress.parse("Openhnm.com"), "https://hnm.com")
        XCTAssertNil(WebAddress.parse("Openhnm"))
    }

    func testNotAnAddress() {
        XCTAssertNil(WebAddress.parse("open notes"))
        XCTAssertNil(WebAddress.parse("open Slack"))
        XCTAssertNil(WebAddress.parse("open the second result"))
        XCTAssertNil(WebAddress.parse("hn.com"))  // no command word
        XCTAssertNil(WebAddress.parse("open file.c"))  // the top-level label needs 2 letters
        XCTAssertNil(WebAddress.parse("open javascript:alert(1)"))
        XCTAssertNil(WebAddress.parse("open slack://open"))
        XCTAssertNil(WebAddress.parse("open 192.168.1.1"))
        XCTAssertNil(WebAddress.parse("Slack me running late."))
    }

    func testRouterGivesOpenURL() async {
        let r = await CommandRouter().route("open hn.com", context: RouteContext(apps: [], names: []))
        XCTAssertEqual(r.intent, .openURL("https://hn.com"))
        XCTAssertEqual(r.tier, .rules)
        XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence)
    }
}
