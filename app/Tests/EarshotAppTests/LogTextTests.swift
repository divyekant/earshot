import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// Gap item 11: the log keeps the command words and a word count for the typed part, never the typed words.
final class LogTextTests: XCTestCase {
    private var folder: URL!

    override func setUp() { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func logText() -> String { (try? String(contentsOf: folder.appendingPathComponent("activity.jsonl"), encoding: .utf8)) ?? "" }

    private func pipeline(_ text: String, runner: CommandActions, front: String?) -> CommandPipeline {
        let engine = TextEngine()
        engine.text = text
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { front })
        p.log = ActivityLog(store: Store(folder: folder))
        return p
    }

    func testChatMessageIsAWordCount() async {
        let runner = DryRunner()
        let r = await pipeline("Slack me, running late", runner: runner, front: nil).finish(mode: .hold)
        guard case .openChat(_, _, let text)? = runner.runs.first?.0 else { return XCTFail(r.note) }
        XCTAssertEqual(text?.lowercased(), "running late", "the action still gets the message")
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(r.heard, "Slack me, (2 words)")
        XCTAssertTrue(r.intent.hasSuffix("type \"(2 words)\""), r.intent)
        let log = logText().lowercased()
        XCTAssertFalse(log.isEmpty)
        XCTAssertFalse(log.contains("running"), log)
        XCTAssertTrue(log.contains("slack me"), "the command words stay")
    }

    func testTypeCommandIsAWordCount() async {
        let runner = FieldRunner()
        let r = await pipeline("type the blue fox jumps", runner: runner, front: "com.anthropic.claudefordesktop").finish(mode: .hold)
        guard case .typeText(let text)? = runner.runs.first?.0 else { return XCTFail(r.note) }
        XCTAssertEqual(text.lowercased(), "the blue fox jumps")
        XCTAssertEqual(r.heard, "type (4 words)")
        XCTAssertEqual(r.intent, "Type \"(4 words)\"")
        XCTAssertFalse(logText().contains("blue fox"), logText())
    }

    func testHoldKeyDictationIsAWordCount() async {
        let runner = FieldRunner()
        let r = await pipeline("Hi, this is a test.", runner: runner, front: "com.anthropic.claudefordesktop").finish(mode: .hold)
        XCTAssertEqual(runner.runs.first?.0, .typeText("Hi, this is a test."))
        XCTAssertEqual(r.heard, "(5 words)")
        XCTAssertFalse(logText().contains("this is a test"), logText())
    }

    func testCommandWithNoTextKeepsItsWords() async {
        let r = await pipeline("open notes", runner: DryRunner(), front: nil).finish(mode: .hold)
        XCTAssertEqual(r.heard, "open notes")
        XCTAssertTrue(logText().contains("open notes"))
    }

    func testWithoutTyped() {
        XCTAssertEqual(CommandPipeline.withoutTyped("Type \"Running late\" in \"Message\"", typed: ["running late"]),
                       "Type \"(2 words)\" in \"Message\"")
        XCTAssertEqual(CommandPipeline.withoutTyped("this is hi", typed: ["hi"]), "this is (1 word)", "whole words only")
        XCTAssertEqual(CommandPipeline.withoutTyped("a (b) c", typed: ["(b)"]), "a (1 word) c", "special characters are text")
        XCTAssertEqual(CommandPipeline.withoutTyped("open notes", typed: []), "open notes")
    }

    func testHeardForLogWhenTheRouterChangedTheWords() {
        // The router took a filler out: the heard text does not contain the typed text. The count replaces the end.
        XCTAssertEqual(CommandPipeline.heardForLog("type um the blue fox", typed: ["the blue fox"]), "type um (3 words)")
        XCTAssertEqual(CommandPipeline.heardForLog("type the, blue fox", typed: ["the blue fox"]), "type (3 words)")
        XCTAssertEqual(CommandPipeline.heardForLog("blue fox", typed: ["the blue fox"]), "(3 words)")
    }

    func testTypedTexts() {
        XCTAssertEqual(CommandPipeline.typedTexts(.openChat(appID: "a", target: "Ravi", text: "late")), ["late"])
        XCTAssertEqual(CommandPipeline.typedTexts(.openChat(appID: "a", target: "Ravi", text: nil)), [])
        XCTAssertEqual(CommandPipeline.typedTexts(.typeInto(elementID: "e1", text: "x")), ["x"])
        XCTAssertEqual(CommandPipeline.typedTexts(.click(elementID: "e1")), [])
        let r = RouteResult(intent: .none, confidence: 0.4, tier: .rules, ms: 0,
                            alternatives: [.typeText("one"), .openChat(appID: "a", target: "b", text: "two")])
        XCTAssertEqual(CommandPipeline.typedTexts(r), ["one", "two"])
    }
}
