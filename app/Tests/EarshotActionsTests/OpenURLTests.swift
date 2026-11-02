import EarshotCore
@testable import EarshotActions
import XCTest

final class OpenURLTests: XCTestCase {
    func testOnlyHttpAndHttpsWithAHost() {
        XCTAssertNotNil(EarshotActionRunner.webURL("https://hn.com"))
        XCTAssertNotNil(EarshotActionRunner.webURL("http://example.com/docs"))
        XCTAssertNil(EarshotActionRunner.webURL("slack://open"))
        XCTAssertNil(EarshotActionRunner.webURL("file:///etc/passwd"))
        XCTAssertNil(EarshotActionRunner.webURL("javascript:alert(1)"))
        XCTAssertNil(EarshotActionRunner.webURL("https://"))
    }
}
