import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// The talk state (gap item 13): one value with named states. Made-up names and text only.
final class TalkStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000_000)
    private var clock = Date(timeIntervalSince1970: 5_000_000)

    private func chain(until: Date) -> CommandPipeline.PendingChain {
        CommandPipeline.PendingChain(steps: ["open notes", "click files"], failed: 1, guess: nil, until: until)
    }

    func testStartsIdle() {
        let s = TalkState()
        XCTAssertEqual(s.name(at: t0), .idle)
        XCTAssertNil(s.until)
        XCTAssertNil(s.lastTyping)
    }

    func testEachWaitHasItsName() {
        var s = TalkState()
        s.textUntil = t0 + 5
        XCTAssertEqual(s.name(at: t0), .waitsForText)
        s.chain = chain(until: t0 + 10)
        XCTAssertEqual(s.name(at: t0), .waitsForChainAnswer)
        s.kept = KeptText(text: "the blue fox", until: t0 + 20)
        XCTAssertEqual(s.name(at: t0), .keepsDroppedWords)
        s.clear()
        XCTAssertEqual(s.name(at: t0), .idle)
    }

    func testANewWaitReplacesTheOldOne() {
        var s = TalkState()
        s.textUntil = t0 + 5
        s.chain = chain(until: t0 + 10)
        XCTAssertNil(s.textUntil, "only one wait at a time")
        XCTAssertNotNil(s.chain)
    }

    func testNilForOneStateDoesNotEndAnotherWait() {
        var s = TalkState()
        s.chain = chain(until: t0 + 10)
        s.textUntil = nil
        s.kept = nil
        s.choice = nil
        XCTAssertNotNil(s.chain, "the chain still waits")
        s.chain = nil
        XCTAssertEqual(s.name(at: t0), .idle)
    }

    func testAWaitWhoseTimeIsOverIsIdle() {
        var s = TalkState()
        s.textUntil = t0 + 5
        XCTAssertEqual(s.name(at: t0 + 5), .waitsForText)
        XCTAssertEqual(s.name(at: t0 + 6), .idle)
    }

    func testTheLastTypingStaysWithAnyWait() {
        var s = TalkState()
        s.lastTyping = TalkState.Typing(at: t0, app: "com.example.notes", text: "see you", alwaysOn: true)
        s.textUntil = t0 + 5
        s.clear()
        XCTAssertEqual(s.lastTyping?.text, "see you", "a wait does not change the last typing")
    }

    // MARK: - The pipeline

    private func make() -> (CommandPipeline, TextEngine, FieldRunner) {
        let engine = TextEngine()
        let runner = FieldRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.anthropic.claudefordesktop" })
        p.now = { [unowned self] in self.clock }
        p.playSounds = false
        return (p, engine, runner)
    }

    func testPipelineNamesTheStateAfterEachTurn() async {
        let (p, e, _) = make()
        XCTAssertEqual(p.talkStateName, .idle)
        e.text = "type"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(p.talkStateName, .waitsForText)

        clock += 2
        e.text = "the blue fox jumps"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(p.talkStateName, .idle, "the armed turn is used up")
        XCTAssertEqual(p.lastTypedText, "the blue fox jumps")
        XCTAssertFalse(p.lastTypedAlwaysOn)

        clock += 6
        XCTAssertEqual(p.talkStateName, .idle)
    }

    func testKeptWordsReplaceAWaitAndOneTurnUsesThem() async {
        let (p, e, runner) = make()
        e.text = "type"
        _ = await p.finish(mode: .hold)
        p.keptText = KeptText(text: "the green owl sleeps", until: clock + CommandPipeline.keptSeconds)
        XCTAssertEqual(p.talkStateName, .keepsDroppedWords)
        XCTAssertNil(p.armedUntil, "the newest note on screen is the one wait")

        clock += 1
        e.text = ""
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.map(\.0), [.typeText("the green owl sleeps")])
        XCTAssertEqual(p.talkStateName, .idle)
    }

    func testSendForgetsTheLastTyping() {
        let (p, _, _) = make()
        p.noteTyped(mode: .alwaysOn, text: "on my way")
        XCTAssertTrue(p.lastTypedAlwaysOn)
        XCTAssertNotNil(p.lastTyped)
        p.forgetTyping()
        XCTAssertNil(p.lastTyped)
        XCTAssertNil(p.lastTypedText)
    }
}
