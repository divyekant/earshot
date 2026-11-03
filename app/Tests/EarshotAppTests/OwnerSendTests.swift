import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// "send" alone in always-on mode, after typing (the owner's choice, D-12, R-ON-5). Made-up text only.
final class OwnerSendTests: XCTestCase {
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

    /// One turn. `voice` is the follow-up voice score that the trigger gives (nil: no check ran).
    @discardableResult
    private func say(_ p: CommandPipeline, _ e: TextEngine, _ text: String, _ mode: InputMode = .alwaysOn,
                     voice: Double? = 0.6) async -> ActivityRecord {
        e.text = text
        p.followUpVoiceScore = mode == .alwaysOn ? voice : nil
        return await p.finish(mode: mode)
    }

    private func typed(_ runs: [(Intent, CommandInfo)]) -> Int {
        runs.filter { CommandPipeline.types($0.0) }.count
    }
    private func sends(_ runs: [(Intent, CommandInfo)]) -> [CommandInfo] {
        runs.filter { $0.0 == .send }.map(\.1)
    }

    func testSendAloneAfterTypingSends() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        XCTAssertEqual(typed(runner.runs), 1)
        clock += 3
        let r = await say(p, e, "send")
        XCTAssertEqual(sends(runner.runs).count, 1, r.note)
        XCTAssertEqual(sends(runner.runs).first?.mode, .alwaysOn)
        XCTAssertEqual(sends(runner.runs).first?.ownerSendAfterTyping, true)
        // One send for one typing.
        clock += 1
        await say(p, e, "send")
        XCTAssertEqual(sends(runner.runs).count, 1)
    }

    func testWakeTurnInTheOwnersVoiceCounts() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 2
        p.pendingWake = WakeHit(phrase: "hey atlas", prerollSeconds: 1.5, voiceScore: 0.62, isOwner: true)
        await say(p, e, "send", voice: nil)
        XCTAssertEqual(sends(runner.runs).count, 1)
    }

    func testTooLate() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 6
        let r = await say(p, e, "send")
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("too late"), r.note)
    }

    func testNoTypingBefore() async {
        let (p, e, runner) = make()
        let r = await say(p, e, "send")
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.hasPrefix("send needs the hold key"), r.note)
    }

    func testVoiceNotChecked() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 1
        let r = await say(p, e, "send", voice: nil)
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("voice not checked"), r.note)
    }

    func testSendToSomeoneIsNotSendAlone() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 1
        await say(p, e, "send it to Sam")
        XCTAssertTrue(sends(runner.runs).isEmpty)
    }

    func testAnotherFrontApp() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 1
        front = "com.tinyspeck.slackmacgap"
        let r = await say(p, e, "send")
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("another app"), r.note)
    }

    func testHoldKeyIsUnchanged() async {
        let (p, e, runner) = make()
        await say(p, e, "send", .hold)
        XCTAssertEqual(sends(runner.runs).count, 1, "the hold key sends with no typing before")
        XCTAssertEqual(sends(runner.runs).first?.mode, .hold)
        XCTAssertEqual(sends(runner.runs).first?.ownerSendAfterTyping, false)
    }

    func testTrailingSendWithTheHoldKeyTypesThenSends() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps and send", .hold)
        XCTAssertEqual(runner.runs.count, 2)
        XCTAssertTrue(CommandPipeline.types(runner.runs[0].0))
        if case .typeInto(_, let t) = runner.runs[0].0 { XCTAssertFalse(t.lowercased().contains("send"), t) }
        if case .typeText(let t) = runner.runs[0].0 { XCTAssertFalse(t.lowercased().contains("send"), t) }
        XCTAssertEqual(runner.runs[1].0, .send)
    }

    func testTrailingSendInAlwaysOnTypesOnly() async {
        let (p, e, runner) = make()
        let r = await say(p, e, "type the blue fox jumps and send")
        XCTAssertEqual(typed(runner.runs), 1)
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("say \"send\" on its own to send"), r.note)
        // Then "send" alone works.
        clock += 2
        await say(p, e, "send")
        XCTAssertEqual(sends(runner.runs).count, 1)
    }

    func testDictationNeverTypesTheSendWords() async {
        let (p, e, runner) = make()
        await say(p, e, "the blue fox jumps and send", .hold)
        XCTAssertEqual(runner.runs.first?.0, .typeText("the blue fox jumps"))
        XCTAssertEqual(runner.runs.last?.0, .send)
    }

    /// The send window also tests the start of the "send" turn.
    func testSendTurnThatStartsInTheWindowSends() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 4
        _ = p.begin()
        clock += 2
        await say(p, e, "send")
        XCTAssertEqual(sends(runner.runs).count, 1)
    }

    func testSendTurnThatStartsAfterTheWindowIsBlocked() async {
        let (p, e, runner) = make()
        await say(p, e, "type the blue fox jumps")
        clock += 5.5
        _ = p.begin()
        clock += 0.5
        let r = await say(p, e, "send")
        XCTAssertTrue(sends(runner.runs).isEmpty)
        XCTAssertTrue(r.note.contains("too late"), r.note)
    }
}
