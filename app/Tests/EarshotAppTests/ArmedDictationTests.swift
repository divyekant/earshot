import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A bare "type", then the text in the next turn (the owner's choice, R-NV-4). Made-up text only.
final class ArmedDictationTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func make(_ setup: (FieldRunner) -> Void = { _ in }) -> (CommandPipeline, TextEngine, FieldRunner) {
        let engine = TextEngine()
        let runner = FieldRunner()
        setup(runner)
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.anthropic.claudefordesktop" })
        p.now = { [unowned self] in self.clock }
        return (p, engine, runner)
    }

    private func say(_ p: CommandPipeline, _ e: TextEngine, _ text: String, _ mode: InputMode) async -> ActivityRecord {
        e.text = text
        return await p.finish(mode: mode)
    }

    func testArmThenTypeWithinTheWindowInAlwaysOn() async {
        let (p, e, runner) = make()
        let armed = await say(p, e, "type.", .alwaysOn)
        XCTAssertTrue(armed.ok)
        XCTAssertEqual(armed.stages["dictation.armed"], 5000)
        XCTAssertNotNil(p.armedUntil)
        XCTAssertTrue(runner.runs.isEmpty, "a bare type does nothing by itself")

        clock += 3
        let typed = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("the blue fox jumps")])
        XCTAssertEqual(runner.runs.first?.1.mode, .alwaysOn, "the action gets the real mode of the turn")
        XCTAssertEqual(typed.heard, "(4 words)", "the log keeps the word count, not the words")
        XCTAssertFalse(typed.note.contains("blue fox"), typed.note)
        XCTAssertNil(p.armedUntil)

        // One turn only: the next plain sentence in always-on is not typed.
        clock += 1
        _ = await say(p, e, "the green owl sleeps", .alwaysOn)
        XCTAssertEqual(runner.runs.count, 1)
    }

    func testHoldKeyArmsToo() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .hold)
        clock += 2
        _ = await say(p, e, "see you at five", .hold)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("see you at five")])
    }

    func testExpiresAfterFiveSeconds() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 6
        let late = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty, late.note)
        XCTAssertNil(p.armedUntil)
    }

    func testSecureFieldIsRefused() async {
        let (p, e, runner) = make { $0.subrole = "AXSecureTextField" }
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        let r = await say(p, e, "made up secret words", .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty)
        // A password field makes the page a sign-in page (SafetyPolicy.sensitive), so that reason comes first.
        XCTAssertEqual(r.note, "type: a sign-in, code or payment page")
    }

    func testNoFocusedFieldLogsTheReason() async {
        let (p, e, runner) = make { $0.focused = nil }
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        let r = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.note, "type: no focused text field")
    }

    func testCommandWordInTheArmedTurnRunsAsACommand() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        _ = await say(p, e, "click market", .alwaysOn)
        XCTAssertEqual(runner.runs.map(\.0), [.click(elementID: "e1")])
        XCTAssertNil(p.armedUntil, "the command uses up the armed turn")
    }

    func testNeverReturnOrSend() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        _ = await say(p, e, "send", .alwaysOn)
        for (intent, _) in runner.runs {
            XCTAssertNotEqual(intent, .send, "always-on never sends")
            if case .typeText(let t) = intent { XCTAssertFalse(t.contains("\n") || t.contains("\r")) }
        }
        XCTAssertFalse(runner.runs.contains { $0.0 == .typeText("send") }, "send is a command word, never typed")
    }
}
