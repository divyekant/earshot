import EarshotActions
import EarshotCore
import EarshotRouter
import XCTest
@testable import EarshotApp

/// A runner for chains: a page with two buttons and a text box. A click on "Broken" fails.
final class ChainRunner: CommandActions {
    var runs: [(Intent, CommandInfo)] = []
    var screens = 0
    func screen() async -> ScreenSnapshot? {
        screens += 1
        return ScreenSnapshot(bundleID: "com.anthropic.claudefordesktop", windowTitle: "Claude", url: "https://claude.ai/chat", elements: [
            ScreenElement(id: "e1", role: "AXButton", label: "Market", risky: false, y: 10),
            ScreenElement(id: "e2", role: "AXButton", label: "Projects", risky: false, y: 20),
            ScreenElement(id: "e3", role: "AXButton", label: "Broken", risky: false, y: 30),
            ScreenElement(id: "e4", role: "AXTextArea", label: "Steer this thread…", risky: false, y: 400),
        ], focusedID: "e4")
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append((intent, command))
        if intent == .click(elementID: "e3") { return ActionOutcome(ok: false, note: "the click did nothing", stages: [:]) }
        return ActionOutcome(ok: true, note: "", stages: ["act": 1])
    }
}

final class ChainTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func make() -> (CommandPipeline, TextEngine, ChainRunner) {
        let engine = TextEngine()
        let runner = ChainRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.anthropic.claudefordesktop" })
        p.now = { [unowned self] in self.clock }
        p.sleepMs = { _ in }
        p.playSounds = false
        return (p, engine, runner)
    }

    // dk's example (2026-11-03): "click on this, click on that, type this and press send".
    func testDksExampleRunsEachStepWithTheHoldKey() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, click on projects, type hello there and press send"
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(runner.runs.count, 4, "\(runner.runs)")
        XCTAssertEqual(runner.runs.prefix(2).map(\.0), [.click(elementID: "e1"), .click(elementID: "e2")])
        XCTAssertTrue(runner.runs.count > 2 && CommandPipeline.types(runner.runs[2].0), "\(runner.runs)")
        XCTAssertEqual(runner.runs.last?.0, .send)
        // A new screen read before each later step.
        XCTAssertEqual(runner.screens, 3)
        for k in ["steps.cut", "step1.route", "step2.screen", "step2.route", "step3.route"] { XCTAssertNotNil(r.stages[k], k) }
    }

    // D-12: in always-on mode, a chain never sends. It types, and says to say "send" on its own.
    func testAlwaysOnChainDoesNotSend() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, type hello there and send"
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertFalse(runner.runs.contains { $0.0 == .send }, "\(runner.runs)")
        XCTAssertTrue(r.intent.contains("say \"send\" on its own"), r.intent)
    }

    // dk: ask first when a step fails. The later steps do not run.
    func testFailedStepStopsAndAsks() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, click on broken, click on projects"
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("step 2 of 3 stopped"), r.note)
        XCTAssertEqual(runner.runs.map(\.0), [.click(elementID: "e1"), .click(elementID: "e3")])
        XCTAssertNotNil(p.pendingChain)

        // "go on" skips the failed step and runs the rest.
        clock += 3
        engine.text = "go on"
        let r2 = await p.finish(mode: .hold)
        XCTAssertTrue(r2.ok, r2.note)
        XCTAssertEqual(runner.runs.last?.0, .click(elementID: "e2"))
        XCTAssertNil(p.pendingChain)
    }

    func testStopEndsTheChain() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, click on broken, click on projects"
        _ = await p.finish(mode: .hold)
        engine.text = "stop"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.count, 2)
        XCTAssertNil(p.pendingChain)
    }

    func testTheStepAgainInNewWordsThenTheRest() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, click on broken, click on projects"
        _ = await p.finish(mode: .hold)
        engine.text = "click on market"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.suffix(2).map(\.0), [.click(elementID: "e1"), .click(elementID: "e2")])
    }

    func testAnAnswerAfterTenSecondsIsANewCommand() async {
        let (p, engine, runner) = make()
        engine.text = "click on market, click on broken, click on projects"
        _ = await p.finish(mode: .hold)
        clock += 11
        engine.text = "go on"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.count, 2, "\(runner.runs)")
    }

    func testMoreThanTenStepsDoesNothing() async {
        let (p, engine, runner) = make()
        engine.text = Array(repeating: "click on market", count: 11).joined(separator: ", ")
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    // One command stays on the old path.
    func testOneCommandIsNotAChain() async {
        let (p, engine, runner) = make()
        engine.text = "click on market"
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(runner.runs.map(\.0), [.click(elementID: "e1")])
        XCTAssertNil(r.stages["steps.cut"])
    }
}
