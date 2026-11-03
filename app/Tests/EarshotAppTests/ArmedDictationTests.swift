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

        // The armed window is one turn only. After 3 s, the go-on window is closed too, so a plain sentence is not typed.
        clock += 4
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
        // The always-on log line also says that no check of the turn voice ran (E6).
        XCTAssertEqual(r.note, "type: a sign-in, code or payment page · speech: voice not checked")
    }

    func testNoFocusedFieldLogsTheReason() async {
        let (p, e, runner) = make { $0.focused = nil }
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        let r = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.note, "type: no focused text field · speech: voice not checked")
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

    /// Live test: a 9.7 s sentence that started 2 s after "type" ended after the 5 s window and was lost.
    /// The window tests the start of the turn (begin()), not its end.
    func testLongTurnThatStartsInTheWindowIsTyped() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 2
        _ = p.begin()
        clock += 9.7
        let r = await say(p, e, "the blue fox jumps over the lazy dog and runs into the green wood", .alwaysOn)
        XCTAssertEqual(runner.runs.count, 1, r.note)
        if case .typeText = runner.runs.first?.0 {} else { XCTFail("typed text expected: \(r.note)") }
    }

    func testTurnThatStartsAfterTheWindowIsNotTyped() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 6
        _ = p.begin()
        clock += 1
        _ = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    /// Live test: a dictated sentence that named "earshot" opened a Slack channel. Only the FIRST sentence counts.
    func testCommandWordLaterInTheTextIsTyped() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        _ = await say(p, e, "the build looks fine. Then open Slack later and tell the team", .alwaysOn)
        XCTAssertEqual(runner.runs.count, 1)
        if case .typeText = runner.runs.first?.0 {} else { XCTFail("typed text expected, got \(String(describing: runner.runs.first?.0))") }
    }

    /// After earshot typed in always-on mode, a turn that starts within 3 s goes on with the text, with one space.
    func testNextTurnGoesOnWithTheText() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .alwaysOn)
        clock += 1
        _ = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertTrue(p.expectsText, "the next turn gets the long pause")
        clock += 2
        _ = p.begin()
        clock += 4
        let r = await say(p, e, "over the lazy dog", .alwaysOn)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("the blue fox jumps"), .typeText(" over the lazy dog")], r.note)
        // A command in the first sentence stays a command.
        clock += 1
        _ = await say(p, e, "click market", .alwaysOn)
        XCTAssertEqual(runner.runs.last?.0, .click(elementID: "e1"))
        XCTAssertFalse(p.expectsText)
    }

    func testGoOnNeedsTheSameAppAndAlwaysOn() async {
        let (p, e, runner) = make()
        _ = await say(p, e, "type", .hold)
        clock += 1
        _ = await say(p, e, "the blue fox jumps", .hold)
        clock += 1
        _ = await say(p, e, "over the lazy dog", .alwaysOn)
        XCTAssertEqual(runner.runs.count, 1, "a hold-key typing does not open the go-on window")
    }

    /// Review of #86: when earshot waits for the owner's words (after "type", or after a typing), it plays no result
    /// sound, so nothing mutes the detector, and the owner can go on at once.
    func testTypingPlaysNoSoundAndTheNextTurnGoesOn() async {
        let (p, e, runner) = make()
        var sounds: [FeedbackSound] = []
        p.playSound = { sounds.append($0) }
        _ = await say(p, e, "type", .alwaysOn)
        XCTAssertTrue(sounds.isEmpty, "the arming waits for words: no sound")
        XCTAssertNil(p.lastSound, "so the app mutes nothing")
        clock += 0.2
        _ = p.begin()
        clock += 2
        _ = await say(p, e, "the blue fox jumps", .alwaysOn)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("the blue fox jumps")], "a text turn 0.2 s after the arming is typed")
        XCTAssertNil(p.lastSound, "a typing plays no sound either")
        clock += 0.2
        _ = p.begin()
        clock += 2
        _ = await say(p, e, "over the lazy dog", .alwaysOn)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("the blue fox jumps"), .typeText(" over the lazy dog")])
        XCTAssertTrue(sounds.isEmpty, "no result sound in the whole dictation")
        // A command that does not wait for words keeps its sound.
        clock += 10
        _ = await say(p, e, "click market", .alwaysOn)
        XCTAssertEqual(sounds, [.done])
    }
}
