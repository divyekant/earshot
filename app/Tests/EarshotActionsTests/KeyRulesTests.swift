import EarshotCore
import XCTest
@testable import EarshotActions

/// Spoken keys and "undo that" (I-34, D-13): the rules of the action module, with no screen. Made-up text only.
final class KeyRulesTests: XCTestCase {
    private let area = KeyFocus(editable: true, multiLine: true, messageBox: false)
    private let box = KeyFocus(editable: true, multiLine: true, messageBox: true)
    private let line = KeyFocus(editable: true, multiLine: false, messageBox: false)
    private let list = KeyFocus(editable: false, multiLine: false, messageBox: false)

    func testReturnNeverInAMessageBox() {
        // Return in a message box can send: only "send" may press it there (R-NV-5).
        XCTAssertNotNil(KeyRules.block(.newLine, times: 1, focus: box, sensitive: nil))
        XCTAssertNotNil(KeyRules.block(.newLine, times: 1, focus: line, sensitive: nil), "a one-line field can submit a form")
        XCTAssertNotNil(KeyRules.block(.newLine, times: 1, focus: list, sensitive: nil))
        XCTAssertNotNil(KeyRules.block(.newLine, times: 1, focus: nil, sensitive: nil))
        XCTAssertNil(KeyRules.block(.newLine, times: 2, focus: area, sensitive: nil))
    }

    func testDeleteKeysOnlyInATextField() {
        // Outside a field, Backspace can delete a selected item (a mail, a file).
        XCTAssertNotNil(KeyRules.block(.backspace, times: 1, focus: list, sensitive: nil))
        XCTAssertNotNil(KeyRules.block(.forwardDelete, times: 1, focus: nil, sensitive: nil))
        XCTAssertNil(KeyRules.block(.backspace, times: 3, focus: line, sensitive: nil))
        XCTAssertNil(KeyRules.block(.backspace, times: 3, focus: box, sensitive: nil))
    }

    func testOtherKeysAnywhere() {
        for key in [SpokenKey.tab, .escape, .left, .right, .up, .down] {
            XCTAssertNil(KeyRules.block(key, times: 1, focus: nil, sensitive: nil), "\(key)")
            XCTAssertNil(KeyRules.block(key, times: 1, focus: list, sensitive: nil), "\(key)")
        }
    }

    func testCountAndSensitivePage() {
        XCTAssertNotNil(KeyRules.block(.tab, times: 0, focus: area, sensitive: nil))
        XCTAssertNotNil(KeyRules.block(.tab, times: KeyRules.maxTimes + 1, focus: area, sensitive: nil))
        XCTAssertNil(KeyRules.block(.tab, times: KeyRules.maxTimes, focus: area, sensitive: nil))
        for key in SpokenKey.allCases {
            XCTAssertNotNil(KeyRules.block(key, times: 1, focus: area, sensitive: "a password field"), "\(key)")
        }
    }

    func testMessageBoxShape() {
        let window = Frame(x: 0, y: 0, w: 1000, h: 800)
        // A short wide box low in the window: a message box.
        XCTAssertTrue(KeyRules.messageBox(labelSaysComposer: false, field: Frame(x: 300, y: 700, w: 680, h: 60), window: window))
        // A tall document body: not a message box, so Return makes a new line.
        XCTAssertFalse(KeyRules.messageBox(labelSaysComposer: false, field: Frame(x: 300, y: 50, w: 700, h: 740), window: window))
        // A label that says "message" wins over the shape.
        XCTAssertTrue(KeyRules.messageBox(labelSaysComposer: true, field: Frame(x: 300, y: 50, w: 700, h: 740), window: window))
        // An unknown shape keeps the strict rule.
        XCTAssertTrue(KeyRules.messageBox(labelSaysComposer: false, field: nil, window: window))
    }

    func testUndoRemovesOnlyTheTypedText() {
        let value = "Notes: the blue fox jumps"
        XCTAssertEqual(KeyRules.undoPlan(typed: "the blue fox jumps", value: value, caret: value.utf16.count), .backspaces(18))
        XCTAssertEqual(KeyRules.undoPlan(typed: "the blue fox jumps", value: value, caret: nil), .backspaces(18))
        // A trailing line end of the field stays out of the count.
        XCTAssertEqual(KeyRules.undoPlan(typed: "the blue fox jumps", value: value + "\n", caret: value.utf16.count), .backspaces(18))
        // The space before go-on text goes too.
        XCTAssertEqual(KeyRules.undoPlan(typed: " over the fence", value: "Fox jumps over the fence", caret: nil), .backspaces(15))
        // Characters that take two UTF-16 units count as one Backspace.
        let cafe = "Order: café ☕️"
        XCTAssertEqual(KeyRules.undoPlan(typed: "café ☕️", value: cafe, caret: cafe.utf16.count), .backspaces(6))
    }

    func testUndoDoesNothingWhenTheFieldChanged() {
        let value = "Notes: the blue fox jumps"
        guard case .blocked = KeyRules.undoPlan(typed: "the blue fox jumps", value: value + " more", caret: nil) else {
            return XCTFail("the owner typed after earshot")
        }
        guard case .blocked = KeyRules.undoPlan(typed: "the blue fox jumps", value: value, caret: 3) else {
            return XCTFail("the cursor moved")
        }
        guard case .blocked = KeyRules.undoPlan(typed: "the blue fox jumps", value: value, caret: -1) else {
            return XCTFail("text is selected: Backspace would remove the selection")
        }
        guard case .blocked = KeyRules.undoPlan(typed: "the blue fox jumps", value: nil, caret: nil) else {
            return XCTFail("no value to check")
        }
        guard case .blocked = KeyRules.undoPlan(typed: "  ", value: value, caret: nil) else {
            return XCTFail("nothing typed")
        }
    }
}
