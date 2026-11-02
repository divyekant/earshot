import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A runner with a focused text field (ScreenSnapshot.focusedID) on the screen.
final class FieldRunner: CommandActions {
    var runs: [(Intent, CommandInfo)] = []
    var subrole = ""
    var focused: String? = "e2"
    var url = "https://claude.ai/chat"
    func screen() async -> ScreenSnapshot? {
        ScreenSnapshot(bundleID: "com.anthropic.claudefordesktop", windowTitle: "Claude", url: url, elements: [
            ScreenElement(id: "e1", role: "AXButton", label: "Market", risky: false, y: 10),
            ScreenElement(id: "e2", role: "AXTextArea", subrole: subrole, label: "Steer this thread…", risky: false, y: 400),
        ], focusedID: focused)
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append((intent, command))
        return ActionOutcome(ok: true, note: "typed", stages: ["typed": 4])
    }
}

final class DictationTests: XCTestCase {
    private func run(_ text: String, mode: InputMode = .hold, _ setup: (FieldRunner) -> Void = { _ in }) async -> (FieldRunner, ActivityRecord) {
        let engine = TextEngine()
        engine.text = text
        let runner = FieldRunner()
        setup(runner)
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.anthropic.claudefordesktop" })
        return (runner, await p.finish(mode: mode))
    }

    func testPlainWordsGoIntoTheFocusedField() async {
        let (runner, r) = await run("Hi, this is a test.")
        XCTAssertEqual(runner.runs.count, 1)
        XCTAssertEqual(runner.runs.first?.0, .typeText("Hi, this is a test."))
        XCTAssertEqual(runner.runs.first?.1.mode, .hold)
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.note.contains("dictation into the focused field"), r.note)
    }

    func testAlwaysOnNeverDictates() async {
        let (runner, _) = await run("Hi, this is a test.", mode: .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testNoFocusedFieldNoTyping() async {
        let (runner, r) = await run("Hi, this is a test.") { $0.focused = nil }
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertFalse(r.ok)
    }

    func testNeverIntoAPasswordField() async {
        let (runner, _) = await run("hunter two") { $0.subrole = "AXSecureTextField" }
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testNeverOnASignInPage() async {
        let (runner, _) = await run("Hi, this is a test.") { $0.url = "https://example.org/login" }
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testCommandWordsStayCommands() async {
        let (runner, _) = await run("click market")
        XCTAssertEqual(runner.runs.first?.0, .click(elementID: "e1"))
        let (r2, _) = await run("send")
        XCTAssertFalse(r2.runs.contains { if case .typeText = $0.0 { return true } else { return false } }, "send is never typed")
    }
}
