import EarshotCore
import Foundation
import XCTest
@testable import EarshotActions

/// T9: where the numbers go on the picture for Jev (D-10).
final class VisionMarksTests: XCTestCase {
    func el(_ id: String, _ label: String, x: Double, y: Double, role: String = "AXButton") -> ScreenElement {
        ScreenElement(id: id, role: role, label: label, risky: SafetyPolicy.isRisky(label, role: role), x: x, y: y, w: 80, h: 24)
    }

    func testMarksSkipOutsideAndNumberRisky() {
        let window = Frame(x: 100, y: 50, w: 1000, h: 800)
        let elements = [
            el("e1", "Settings", x: 150, y: 70),
            el("e2", "Send", x: 300, y: 70),          // risky: a number, so Jev can point at it; earshot refuses it
            el("e3", "Help", x: 2000, y: 70),         // outside the window
            el("m:Edit>Select All", "Select All", x: 0, y: 0),  // a menu item has no place on the picture
            el("e4", "Inbox", x: 100, y: 840),
        ]
        let marks = VisionMarks.place(elements, window: window, k: 1.5, pictureHeight: 1200)
        XCTAssertEqual(marks.map(\.number), [1, 2, 4])
        // e1: 50 points right and 20 points down from the window corner, at 1.5 pixels for each point.
        XCTAssertEqual(marks[0].x, 75, accuracy: 0.001)
        XCTAssertEqual(marks[0].y, 1200 - 30 - Double(VisionMarks.badgeHeight), accuracy: 0.001)
        // e4 at the bottom edge: the badge stays inside the picture.
        XCTAssertGreaterThanOrEqual(marks[2].y, 0)
    }

    /// A pick from the screenshot fallback runs with the tier "jev". Then a risky label is never pressed,
    /// even if the owner said the exact label (R-NV-5).
    func testJevTierNeverPressesRisky() {
        let jev = CommandInfo(mode: .hold, tier: .jev, spokenTarget: "send")
        XCTAssertNotNil(ActionRules.pressBlock(label: "Send", role: "AXButton", command: jev, sensitive: nil))
        XCTAssertNotNil(ActionRules.pressBlock(label: "Delete account", role: "AXLink", command: jev, sensitive: nil))
        XCTAssertNil(ActionRules.pressBlock(label: "Settings", role: "AXButton", command: jev, sensitive: nil))
        // A sensitive page blocks every press.
        XCTAssertNotNil(ActionRules.pressBlock(label: "Settings", role: "AXButton", command: jev, sensitive: "a password field"))
    }
}
