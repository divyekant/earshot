import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A picker that only counts. The fake runner calls it, like the real visionTarget does.
final class CountingPicker: ScreenPicker, @unchecked Sendable {
    var calls = 0
    func pick(_ command: String, shot: VisionShot, budgetMs: Int) async -> VisionPick { calls += 1; return .none }
}

/// A runner with a screen and a fixed screenshot answer.
final class VisionRunner: CommandActions {
    var answer = VisionTarget(elementID: nil, label: "", note: "Jev found no target on the screen", stages: ["shot": 40, "jev": 900])
    var runs: [(Intent, CommandInfo)] = []
    var visionCalls: [(String, InputMode, Int)] = []
    let elements = [ScreenElement(id: "e1", role: "AXLink", label: "Market", risky: false, y: 10)]
    func screen() async -> ScreenSnapshot? { ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "t", url: "https://example.org", elements: elements) }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append((intent, command))
        return ActionOutcome(ok: true, note: "dry run", stages: ["pressed": 3])
    }
    func visionTarget(_ command: String, mode: InputMode, picker: ScreenPicker, budgetMs: Int) async -> VisionTarget {
        visionCalls.append((command, mode, budgetMs))
        _ = await picker.pick(command, shot: VisionShot(jpeg: Data(), marks: [], width: 0, height: 0), budgetMs: budgetMs)
        return answer
    }
}

final class VisionWiringTests: XCTestCase {
    private func make(_ text: String, router: Router = CommandRouter(), picker: ScreenPicker?) -> (CommandPipeline, VisionRunner) {
        let engine = TextEngine()
        engine.text = text
        let runner = VisionRunner()
        let p = CommandPipeline(engine: engine, router: router, actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.google.Chrome" })
        p.picker = picker
        p.jevScreenBudgetMs = 1200
        return (p, runner)
    }
    private let unsure = RouteResult(intent: .none, confidence: 0.5, tier: .none, ms: 1, why: "no label matches")

    func testOffByDefaultMakesNoCall() async {
        let (p, runner) = make("click the blue widget", picker: nil)
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.visionCalls.isEmpty)
        XCTAssertNil(ScreenPickerFactory.make(EarshotSettings(), jevKey: "k"), "the setting is off by default")
    }

    func testAlwaysOnMakesNoCall() async {
        let picker = CountingPicker()
        let (p, runner) = make("earshot click the blue widget", router: FixedRouter(result: unsure), picker: picker)
        _ = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(runner.visionCalls.isEmpty)
        XCTAssertEqual(picker.calls, 0)
    }

    func testBlockedRouteMakesNoCall() async {
        let blocked = RouteResult(intent: .none, confidence: 0.9, tier: .fuzzy, ms: 1, why: "blocked: risky label \"Delete account\"")
        let (p, runner) = make("click delete acount", router: FixedRouter(result: blocked), picker: CountingPicker())
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.visionCalls.isEmpty)
    }

    func testSureRouteMakesNoCall() async {
        let (p, runner) = make("click market", picker: CountingPicker())
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.visionCalls.isEmpty)
        XCTAssertEqual(runner.runs.first?.0, .click(elementID: "e1"))
    }

    func testNotForTypingAppsOrChats() {
        let open = RouteResult(intent: .openApp(appID: "slack"), confidence: 0.4, tier: .fuzzy, ms: 1)
        XCTAssertFalse(CommandPipeline.mayAskScreen("open slack", open))
        XCTAssertFalse(CommandPipeline.mayAskScreen("search for cats", unsure), "typing is not a press")
        XCTAssertFalse(CommandPipeline.mayAskScreen("scroll down", unsure))
        XCTAssertFalse(CommandPipeline.mayAskScreen("send", unsure))
        XCTAssertFalse(CommandPipeline.mayAskScreen("slack me running late", unsure))
        XCTAssertTrue(CommandPipeline.mayAskScreen("click the blue widget", unsure))
        let weakClick = RouteResult(intent: .click(elementID: "e1"), confidence: 0.5, tier: .fuzzy, ms: 1)
        XCTAssertTrue(CommandPipeline.mayAskScreen("click market", weakClick))
    }

    func testUnsurePressMakesOneCallAndAJevClick() async {
        let picker = CountingPicker()
        let (p, runner) = make("click the blue widget", router: FixedRouter(result: unsure), picker: picker)
        runner.answer = VisionTarget(elementID: "e7", label: "Blue widget", note: "mark 7", stages: ["shot": 40, "jev": 900, "check": 2])
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(runner.visionCalls.count, 1)
        XCTAssertEqual(picker.calls, 1)
        XCTAssertEqual(runner.visionCalls.first?.2, 1200, "the budget comes from the settings")
        XCTAssertEqual(runner.runs.count, 1)
        XCTAssertEqual(runner.runs.first?.0, .click(elementID: "e7"))
        XCTAssertEqual(runner.runs.first?.1.tier, .jev)
        XCTAssertEqual(runner.runs.first?.1.mode, .hold)
        XCTAssertEqual(runner.runs.first?.1.spokenTarget, CommandRouter.spokenTarget("click the blue widget"))
        XCTAssertEqual(r.tier, .jev)
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.note.contains("Jev (screen): Blue widget"), r.note)
        XCTAssertEqual(r.stages["vision.shot"], 40)
        XCTAssertEqual(r.stages["vision.jev"], 900)
        XCTAssertEqual(r.stages["vision.check"], 2)
    }

    func testNilPickKeepsTheNotSureNote() async {
        let (p, runner) = make("click the blue widget", router: FixedRouter(result: unsure), picker: CountingPicker())
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(runner.visionCalls.count, 1)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("not sure"), r.note)
        XCTAssertTrue(r.note.contains("Jev (screen): Jev found no target on the screen"), r.note)
    }
}
