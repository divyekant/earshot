import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A note that records its time on screen.
final class TimedNotes: FeedbackSink, TimedFeedback {
    var shown: [(text: String, seconds: Double?)] = []
    func show(_ text: String, ok: Bool) { shown.append((text, nil)) }
    func show(_ text: String, ok: Bool, seconds: Double) { shown.append((text, seconds)) }
    func hide() {}
}

/// A page whose element ids change on each read, as a new AX read can number them in a new order.
final class MovingRunner: CommandActions {
    var runs: [(Intent, CommandInfo)] = []
    var reads = 0
    var bundleID = "com.google.Chrome"
    func screen() async -> ScreenSnapshot? {
        reads += 1
        let k = reads * 10
        return ScreenSnapshot(bundleID: bundleID, windowTitle: "Page", url: "https://example.com/", elements: [
            ScreenElement(id: "e\(k + 1)", role: "AXButton", label: "Projects", risky: false, x: 10, y: 10),
            ScreenElement(id: "e\(k + 2)", role: "AXButton", label: "Project", risky: false, x: 10, y: 40),
            ScreenElement(id: "e\(k + 3)", role: "AXButton", label: "Delete project", risky: true, x: 10, y: 70),
        ])
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append((intent, command))
        return ActionOutcome(ok: true, note: "", stages: ["act": 1])
    }
}

/// The answer to a "not sure" note for one command (gap item 5). Made-up names only.
final class ChoiceTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 3_000_000)
    /// The same name in two chat apps: the rules score both the same ("two chats match").
    static let names = Fixture.names + [
        NameEntry(appID: "slack", name: "Nadia Brook", source: .sidebar),
        NameEntry(appID: "messages", name: "Nadia Brook", source: .sidebar),
    ]

    private func make() -> (CommandPipeline, TextEngine, DryRunner, TimedNotes) {
        let engine = TextEngine()
        let runner = DryRunner()
        // Notes is in front: no chat app gets the front-app lean.
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Self.names }, frontBundleID: { "com.apple.Notes" })
        let notes = TimedNotes()
        p.feedback = notes
        p.now = { [unowned self] in self.clock }
        p.playSounds = false
        return (p, engine, runner, notes)
    }

    @discardableResult
    private func say(_ p: CommandPipeline, _ e: TextEngine, _ text: String, _ mode: InputMode = .hold,
                     voice passed: Bool = true) async -> ActivityRecord {
        e.text = text
        p.turnVoice = mode == .alwaysOn
            ? TurnVoice(kind: .followUp, score: passed ? 0.6 : 0.2, seconds: 0.5, audioSeconds: 0.9, limit: 0.35, passed: passed)
            : nil
        return await p.finish(mode: mode)
    }

    private func chats(_ runs: [(Intent, CommandInfo)]) -> [String] {
        runs.compactMap { if case .openChat(let app, _, _) = $0.0 { return app } else { return nil } }
    }

    func testTieShowsTwoChoicesForTenSeconds() async {
        let (p, e, runner, notes) = make()
        let r = await say(p, e, "ping Nadia Brook, running late")
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("not sure: two chats match"), r.note)
        XCTAssertTrue(r.note.contains("1: → ") && r.note.contains("2: → "), r.note)
        XCTAssertTrue(r.note.contains("\"the second one\""), r.note)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(p.pendingChoice?.choices.count, 2)
        XCTAssertEqual(notes.shown.last?.seconds, CommandPipeline.choiceAnswerSeconds)
    }

    func testTheSecondOneOpensTheOtherChat() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late")
        let first = p.pendingChoice?.choices.first?.intent
        clock += 4
        let r = await say(p, e, "The second one.")
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(runner.runs.count, 1)
        guard case .openChat(_, let target, let text) = runner.runs[0].0 else { return XCTFail("\(runner.runs)") }
        XCTAssertNotEqual(runner.runs[0].0, first)
        XCTAssertEqual(target, "Nadia Brook")
        XCTAssertEqual(text, "running late")
        // A choice never runs at the tier .rules (SafetyPolicy.mayPress).
        XCTAssertEqual(runner.runs[0].1.tier, .fuzzy)
        XCTAssertNil(p.pendingChoice)
        XCTAssertTrue(r.note.contains("your answer to: not sure (two chats match)"), r.note)
    }

    func testYesOpensTheFirstChoice() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late")
        let first = p.pendingChoice?.choices.first?.intent
        await say(p, e, "yes")
        XCTAssertEqual(runner.runs.map(\.0), first.map { [$0] } ?? [])
    }

    func testNoDoesNothing() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late")
        let r = await say(p, e, "no")
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.note.components(separatedBy: " · ").first, "OK, nothing done")
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertNil(p.pendingChoice)
    }

    func testAnAnswerAfterTenSecondsIsANewCommand() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late")
        clock += 11
        let r = await say(p, e, "yes")
        XCTAssertTrue(runner.runs.isEmpty, "\(runner.runs)")
        XCTAssertFalse(r.note.contains("your answer"), r.note)
    }

    func testANewCommandClearsTheNote() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late")
        await say(p, e, "open Notes")
        XCTAssertEqual(runner.runs.map(\.0), [.openApp(appID: "notes")])
        XCTAssertNil(p.pendingChoice)
        // The note is gone: a later "yes" does nothing.
        await say(p, e, "yes")
        XCTAssertEqual(runner.runs.count, 1)
    }

    // In always-on mode, only the owner's checked voice can answer.
    func testAlwaysOnAnswerNeedsTheOwnersVoice() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late", .alwaysOn)
        XCTAssertNotNil(p.pendingChoice)
        await say(p, e, "yes", .alwaysOn, voice: false)
        XCTAssertTrue(runner.runs.isEmpty, "\(runner.runs)")

        await say(p, e, "ping Nadia Brook, running late", .alwaysOn)
        await say(p, e, "yes", .alwaysOn)
        XCTAssertEqual(chats(runner.runs).count, 1)
    }

    // "… and send" with the hold key in both turns: type, then send through the normal send rules.
    func testHoldKeyAndSendSendsAfterTheAnswer() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late and send")
        XCTAssertEqual(p.pendingChoice?.sendAfter, true)
        await say(p, e, "the first one")
        XCTAssertEqual(runner.runs.map(\.0).last, .send)
        guard case .openChat(_, _, let text) = runner.runs.first?.0 else { return XCTFail("\(runner.runs)") }
        XCTAssertEqual(text, "running late")
    }

    // D-12: in always-on mode, the answer never sends. The owner says "send" on its own.
    func testAlwaysOnAnswerDoesNotSend() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late and send", .alwaysOn)
        let r = await say(p, e, "yes", .alwaysOn)
        XCTAssertFalse(runner.runs.contains { $0.0 == .send }, "\(runner.runs)")
        XCTAssertEqual(chats(runner.runs).count, 1)
        XCTAssertTrue(r.note.contains("say \"send\" on its own"), r.note)
    }

    // A hold-key command and an always-on answer: no send.
    func testHoldCommandAlwaysOnAnswerDoesNotSend() async {
        let (p, e, runner, _) = make()
        await say(p, e, "ping Nadia Brook, running late and send")
        await say(p, e, "yes", .alwaysOn)
        XCTAssertFalse(runner.runs.contains { $0.0 == .send }, "\(runner.runs)")
    }

    // A click choice finds the same element on the new screen read. A risky element is never a choice.
    func testClickChoiceFindsTheElementAgainAndSkipsRisky() async {
        let engine = TextEngine()
        let runner = MovingRunner()
        let unsure = RouteResult(intent: .click(elementID: "e11"), confidence: 0.5, tier: .fuzzy, ms: 0, why: "two labels match",
                                 alternatives: [.click(elementID: "e13"), .click(elementID: "e12")])
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: unsure), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { [] }, frontBundleID: { "com.google.Chrome" })
        p.now = { [unowned self] in self.clock }
        p.playSounds = false
        engine.text = "click project"
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(p.pendingChoice?.choices.map(\.describe), ["Click \"Projects\"", "Click \"Project\""], r.note)
        engine.text = "the second one"
        let r2 = await p.finish(mode: .hold)
        XCTAssertTrue(r2.ok, r2.note)
        // The second read numbers the elements from e21.
        XCTAssertEqual(runner.runs.map(\.0), [.click(elementID: "e22")])
    }

    func testClickChoiceInAnotherAppFails() async {
        let engine = TextEngine()
        let runner = MovingRunner()
        let unsure = RouteResult(intent: .click(elementID: "e11"), confidence: 0.5, tier: .fuzzy, ms: 0, why: "two labels match",
                                 alternatives: [.click(elementID: "e12")])
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: unsure), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { [] }, frontBundleID: { "com.google.Chrome" })
        p.now = { [unowned self] in self.clock }
        p.playSounds = false
        engine.text = "click project"
        _ = await p.finish(mode: .hold)
        runner.bundleID = "com.apple.Notes"
        engine.text = "yes"
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("the screen changed"), r.note)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testAnswerWords() {
        let cases: [(String, CommandPipeline.ChoiceAnswer?)] = [
            ("yes", .pick(0)), ("Yeah.", .pick(0)), ("the first one", .pick(0)), ("number one", .pick(0)), ("1", .pick(0)),
            ("OK, do it", .pick(0)), ("The second one.", .pick(1)), ("second", .pick(1)), ("the other one", .pick(1)),
            ("yes, the second one", .pick(1)), ("number 2", .pick(1)), ("No.", .no), ("never mind", .no), ("cancel", .no),
            ("open Slack", nil), ("the second tab", nil), ("thank you", nil), ("yes and no", nil),
        ]
        for (text, want) in cases { XCTAssertEqual(CommandPipeline.choiceAnswer(text), want, text) }
    }

    func testOneChoiceNote() {
        let one = [CommandPipeline.Choice(intent: .openApp(appID: "slack"), describe: "→ Slack", element: nil)]
        XCTAssertEqual(CommandPipeline.choiceNote("weak name match", one), "not sure: weak name match · say \"yes\" for: → Slack, or \"no\"")
        XCTAssertEqual(CommandPipeline.choiceNote("nothing matches", []), "not sure: nothing matches")
    }
}
