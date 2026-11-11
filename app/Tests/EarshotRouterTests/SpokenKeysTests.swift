import EarshotCore
import XCTest
@testable import EarshotRouter

/// Spoken keys and "undo that" (I-34, D-13). Text only: no screen and no keys. Made-up text only.
final class SpokenKeysTests: XCTestCase {
    private func route(_ text: String, _ context: RouteContext = Fixtures.context) async -> RouteResult {
        await CommandRouter().route(text, context: context)
    }

    private func expect(_ words: String, _ intent: Intent, file: StaticString = #filePath, line: UInt = #line) async {
        let r = await route(words)
        XCTAssertEqual(r.intent, intent, "\"\(words)\": \(r.why)", file: file, line: line)
        XCTAssertEqual(r.tier, .rules, "\"\(words)\"", file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence, file: file, line: line)
    }

    func testKeys() async {
        await expect("backspace", .pressKey(.backspace, times: 1))
        await expect("press backspace three times", .pressKey(.backspace, times: 3))
        await expect("Backspace 5 times.", .pressKey(.backspace, times: 5))
        await expect("delete twice", .pressKey(.backspace, times: 2))
        await expect("press delete", .pressKey(.backspace, times: 1))
        await expect("forward delete", .pressKey(.forwardDelete, times: 1))
        await expect("new line", .pressKey(.newLine, times: 1))
        await expect("New line.", .pressKey(.newLine, times: 1))
        await expect("new line two times", .pressKey(.newLine, times: 2))
        await expect("hit enter", .pressKey(.newLine, times: 1))
        await expect("press return", .pressKey(.newLine, times: 1))
        await expect("press tab", .pressKey(.tab, times: 1))
        await expect("hit the tab key", .pressKey(.tab, times: 1))
        await expect("escape", .pressKey(.escape, times: 1))
        await expect("press the escape key", .pressKey(.escape, times: 1))
        await expect("left arrow", .pressKey(.left, times: 1))
        await expect("Right arrow 3 times", .pressKey(.right, times: 3))
        await expect("press up", .pressKey(.up, times: 1))
        await expect("down arrow twice", .pressKey(.down, times: 2))
        await expect("uh, press tab please", .pressKey(.tab, times: 1))
    }

    func testUndo() async {
        await expect("undo that", .undoTyping(""))
        await expect("Scratch that.", .undoTyping(""))
        await expect("delete that", .undoTyping(""))
    }

    func testWordsThatStayOtherCommands() async {
        // A bare word that is also a command or a menu title needs a key verb or a count.
        for words in ["delete", "enter", "return", "tab", "up", "down", "esc"] {
            let r = await route(words)
            if case .pressKey = r.intent { XCTFail("\"\(words)\" is not a key on its own: \(r.why)") }
        }
        // Text after a key name is not a count.
        for words in ["enter the blue fox", "tab over to the left", "new line of credit", "delete the old draft"] {
            let r = await route(words)
            if case .pressKey = r.intent { XCTFail("\"\(words)\": \(r.why)") }
        }
        // "scroll down" stays a scroll.
        let scroll = await route("scroll down")
        XCTAssertEqual(scroll.intent, .scroll(.down), scroll.why)
    }

    func testCount() {
        XCTAssertEqual(CommandRouter.keyCount([]), 1)
        XCTAssertEqual(CommandRouter.keyCount(["once"]), 1)
        XCTAssertEqual(CommandRouter.keyCount(["twice"]), 2)
        XCTAssertEqual(CommandRouter.keyCount(["twelve", "times"]), 12)
        XCTAssertEqual(CommandRouter.keyCount(["40", "times"]), 40, "the action module blocks more than 20, with a note")
        XCTAssertNil(CommandRouter.keyCount(["of", "credit"]))
    }

    func testKeysAreCommandsForDictation() {
        // Dictation types plain words. A key phrase is a command, also as the first sentence after "type".
        let ctx = Fixtures.context
        XCTAssertTrue(CommandRouter.hasCommandWord("new line", context: ctx))
        XCTAssertTrue(CommandRouter.startsWithCommand("Backspace three times.", context: ctx))
        XCTAssertTrue(CommandRouter.startsWithCommand("undo that", context: ctx))
    }
}
