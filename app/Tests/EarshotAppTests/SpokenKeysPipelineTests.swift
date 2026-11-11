import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// Spoken keys and "undo that" in the command path (I-34, D-13). Made-up text only.
final class SpokenKeysPipelineTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 2_000_000)
    private var front = "com.anthropic.claudefordesktop"

    private func make() -> (CommandPipeline, TextEngine, FieldRunner) {
        let engine = TextEngine()
        let runner = FieldRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { [unowned self] in self.front })
        p.now = { [unowned self] in self.clock }
        return (p, engine, runner)
    }

    @discardableResult
    private func say(_ p: CommandPipeline, _ e: TextEngine, _ text: String, _ mode: InputMode = .hold,
                     voice: Double? = 0.6) async -> ActivityRecord {
        e.text = text
        p.turnVoice = mode == .alwaysOn ? voice.map {
            TurnVoice(kind: .followUp, score: $0, seconds: 0.5, audioSeconds: 0.9, limit: 0.35, passed: true)
        } : nil
        return await p.finish(mode: mode)
    }

    private func undos(_ runs: [(Intent, CommandInfo)]) -> [String] {
        runs.compactMap { if case .undoTyping(let t) = $0.0 { return t } else { return nil } }
    }

    func testKeyRunsAndIsNotTyped() async {
        let (p, e, runner) = make()
        let r = await say(p, e, "backspace three times")
        XCTAssertEqual(runner.runs.map(\.0), [.pressKey(.backspace, times: 3)], r.note)
        let (p2, e2, runner2) = make()
        await say(p2, e2, "New line.")
        XCTAssertEqual(runner2.runs.map(\.0), [.pressKey(.newLine, times: 1)], "dictation never types a key phrase")
    }

    func testAlwaysOnNewLineNeedsTheOwnersVoice() async {
        let (p, e, runner) = make()
        let r = await say(p, e, "new line", .alwaysOn, voice: nil)
        XCTAssertTrue(runner.runs.isEmpty, r.note)
        XCTAssertTrue(r.note.contains("new line needs"), r.note)
        await say(p, e, "new line", .alwaysOn, voice: 0.6)
        XCTAssertEqual(runner.runs.map(\.0), [.pressKey(.newLine, times: 1)])
        // Other keys need no voice check.
        await say(p, e, "press tab", .alwaysOn, voice: nil)
        XCTAssertEqual(runner.runs.last?.0, .pressKey(.tab, times: 1))
    }

    func testUndoRemovesTheLastTyping() async {
        let (p, e, runner) = make()
        await say(p, e, "The blue fox jumps.")
        clock += 10
        let r = await say(p, e, "undo that")
        XCTAssertEqual(undos(runner.runs), ["The blue fox jumps."], r.note)
        XCTAssertFalse(r.intent.contains("blue fox"), "the log never keeps the typed text: \(r.intent)")
        XCTAssertFalse(r.note.contains("blue fox"), r.note)
        // One undo for one typing.
        clock += 1
        let again = await say(p, e, "undo that")
        XCTAssertEqual(undos(runner.runs).count, 1, again.note)
        XCTAssertTrue(again.note.contains("nothing that earshot typed"), again.note)
    }

    func testUndoAfterAlwaysOnTyping() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps", .alwaysOn)
        clock += 1
        await say(p, e, "undo that", .alwaysOn)
        XCTAssertEqual(undos(runner.runs).count, 1)
        XCTAssertTrue(undos(runner.runs).first?.contains("blue fox jumps") ?? false, "\(undos(runner.runs))")
        // After the undo, "send" alone has no typing to follow (D-12).
        clock += 1
        await say(p, e, "send", .alwaysOn)
        XCTAssertFalse(runner.runs.contains { $0.0 == .send })
    }

    func testUndoNeverAcrossApps() async {
        let (p, e, runner) = make()
        await say(p, e, "The blue fox jumps.")
        front = "com.tinyspeck.slackmacgap"
        let r = await say(p, e, "undo that")
        XCTAssertTrue(undos(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("another app"), r.note)
    }

    func testUndoTooLate() async {
        let (p, e, runner) = make()
        await say(p, e, "The blue fox jumps.")
        clock += CommandPipeline.undoSeconds + 1
        let r = await say(p, e, "undo that")
        XCTAssertTrue(undos(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("too late"), r.note)
    }

    func testUndoWithNoTyping() async {
        let (p, e, runner) = make()
        let r = await say(p, e, "scratch that")
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertFalse(r.ok)
    }
}
