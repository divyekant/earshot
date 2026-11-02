import EarshotActions
import EarshotDiscovery
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import EarshotSpeech
import XCTest

// Unit tests of the T7 command path, with a fake speech engine, a fake action runner and fake names.
// Nothing here opens an app, presses a key or uses the microphone.

final class TextEngine: SpeechEngine {
    let id = "fake"
    var text = ""
    var began = 0
    var onPartial: (@Sendable (String) -> Void)?
    func prepare() async throws {}
    func begin() throws { began += 1 }
    func end() async throws -> Utterance { Utterance(text: text, engine: id, ms: 1) }
}

final class DryRunner: CommandActions {
    var runs: [(Intent, CommandInfo)] = []
    func screen() async -> ScreenSnapshot? { nil }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append((intent, command))
        return ActionOutcome(ok: true, note: "dry run", stages: ["focus": 1])
    }
}

final class FakeNames: NameFinder {
    var found: [NameEntry] = []
    var searches: [(String, String)] = []
    func names(appID: String) async -> [NameEntry] { [] }
    func search(appID: String, term: String) async -> [NameEntry] {
        searches.append((appID, term))
        return found
    }
}

struct FixedRouter: Router {
    var result: RouteResult
    func route(_ text: String, context: RouteContext) async -> RouteResult { result }
}

enum Fixture {
    static let apps = [
        AppEntry(id: "slack", name: "Slack", bundleID: "com.tinyspeck.slackmacgap", aliases: ["slack"], isChat: true,
                 openChat: .switcher(keys: "cmd+k"), electron: true, approved: true),
        AppEntry(id: "messages", name: "Messages", bundleID: "com.apple.MobileSMS", aliases: ["imessage", "messages", "text"],
                 isChat: true, openChat: .switcher(keys: "cmd+n"), approved: true),
        AppEntry(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome", aliases: ["chrome"], approved: true),
        AppEntry(id: "notes", name: "Notes", bundleID: "com.apple.Notes", approved: true),
    ]
    static let names = [
        NameEntry(appID: "slack", name: "Divyekant Gupta", isSelf: true, source: .sidebar),
        NameEntry(appID: "messages", name: "Divyekant Gupta", isSelf: true, source: .sidebar),
        NameEntry(appID: "slack", name: "Prakash Iyer", source: .sidebar),
        NameEntry(appID: "slack", name: "alerts", source: .sidebar),
        NameEntry(appID: "messages", name: "Mrunal", source: .sidebar),
    ]
}

final class CommandPipelineTests: XCTestCase {
    private func make(_ text: String, router: Router = CommandRouter(), names: [NameEntry] = Fixture.names,
                      finder: FakeNames = FakeNames()) -> (CommandPipeline, TextEngine, DryRunner) {
        let engine = TextEngine()
        engine.text = text
        let runner = DryRunner()
        let p = CommandPipeline(engine: engine, router: router, actions: runner, names: finder,
                                apps: { Fixture.apps }, allNames: { names }, frontBundleID: { nil })
        return (p, engine, runner)
    }

    func testHoldKeyCommandRunsTheIntent() async {
        let (p, engine, runner) = make("Slack me, running late")
        XCTAssertNil(p.begin())
        XCTAssertEqual(engine.began, 1)
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(runner.runs.count, 1)
        guard case .openChat(let app, let target, let text)? = runner.runs.first?.0 else { return XCTFail("\(runner.runs)") }
        XCTAssertEqual(app, "slack")
        XCTAssertEqual(target, "Divyekant Gupta")
        XCTAssertEqual(text?.lowercased(), "running late")
        XCTAssertEqual(runner.runs.first?.1.mode, .hold)
        for stage in ["speech", "screen", "route", "total"] { XCTAssertNotNil(r.stages[stage], stage) }
    }

    func testAlwaysOnDropsTalkThatIsNotForEarshot() async {
        let (p, _, runner) = make("I think the meeting moved to Thursday")
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("not for earshot"), r.note)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testAlwaysOnNeverSendsFromASentence() async {
        let send = RouteResult(intent: .send, confidence: 1, tier: .rules, ms: 0, why: "test")
        let (p, _, runner) = make("message the team and send it", router: FixedRouter(result: send))
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(runner.runs.isEmpty, "a send inside a sentence must not run (R-ON-5)")
    }

    func testHoldKeySendRuns() async {
        let send = RouteResult(intent: .send, confidence: 1, tier: .rules, ms: 0, why: "test")
        let (p, _, runner) = make("send", router: FixedRouter(result: send))
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.first?.0, .send)
    }

    func testLowConfidenceDoesNothing() async {
        let unsure = RouteResult(intent: .openApp(appID: "notes"), confidence: 0.3, tier: .rules, ms: 0, why: "two apps match",
                                 alternatives: [.openApp(appID: "slack")])
        let (p, _, runner) = make("open no", router: FixedRouter(result: unsure))
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("not sure"), r.note)
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testUnknownNameUsesTheAppSearchOnce() async {
        let finder = FakeNames()
        finder.found = [NameEntry(appID: "slack", name: "Ravi Kumar", source: .search)]
        let (p, _, runner) = make("Slack Ravi", finder: finder)
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(finder.searches.count, 1)
        XCTAssertEqual(finder.searches.first?.0, "slack")
        XCTAssertNotNil(r.stages["search"])
        guard case .openChat(_, let target, _)? = runner.runs.first?.0 else { return XCTFail("no chat opened: \(r.note)") }
        XCTAssertEqual(target, "Ravi Kumar")
    }

    func testNoAppSearchForTheOwnChat() async {
        // First live test: "Slack me running late" (no comma) searched Slack for "running late".
        let finder = FakeNames()
        let (p, _, _) = make("Slack me running late", finder: finder)
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(finder.searches.isEmpty, "\(finder.searches)")
    }

    func testNoAppSearchWhenTheRouteIsSure() async {
        let finder = FakeNames()
        let sure = RouteResult(intent: .openChat(appID: "slack", target: "Prakash Iyer", text: nil), confidence: 0.95,
                               tier: .rules, ms: 0, why: "name match")
        let (p, _, runner) = make("Slack Prakash extra words", router: FixedRouter(result: sure), finder: finder)
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(finder.searches.isEmpty)
        XCTAssertEqual(runner.runs.count, 1)
    }

    func testLogKeepsTheRouteReason() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (p, _, _) = make("open notes")
        p.log = ActivityLog(store: Store(folder: folder))
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.note.contains("route:"), r.note)
    }

    func testTypingPausesAlwaysOn() async {
        let (p, _, _) = make("Slack me, buy milk")
        var pauses: [Bool] = []
        p.pauseAlwaysOn = { pauses.append($0) }
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(pauses, [true, false])
    }

    func testEmptyTextIsQuiet() async {
        let (p, _, runner) = make("   ")
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.note, "no words")
        XCTAssertTrue(runner.runs.isEmpty)
    }

    func testTestHookDryRunDoesNotAct() async {
        let (p, _, runner) = make("")
        let report = await p.test("open notes", runActions: false)
        XCTAssertEqual(report.route.intent, .openApp(appID: "notes"))
        XCTAssertNil(report.outcome)
        XCTAssertTrue(runner.runs.isEmpty)
        let ran = await p.test("open notes", runActions: true)
        XCTAssertEqual(ran.outcome?.note, "dry run")
    }
}

final class NoteRecorder: FeedbackSink {
    var shown: [(String, Bool)] = []
    func show(_ text: String, ok: Bool) { shown.append((text, ok)) }
    func hide() {}
}

final class DiscoverHookTests: XCTestCase {
    func testAccessibilityOffShowsTheErrorAndKeepsTheRows() async {
        let note = NoteRecorder()
        let current = [Fixture.apps[0]]
        let rows = await AppController.discover(refresh: { throw DiscoveryError.accessibilityOff }, current: current, feedback: note)
        XCTAssertEqual(rows, current)
        XCTAssertEqual(note.shown.first?.0, "Discover apps: Turn on Accessibility for earshot first")
        XCTAssertEqual(note.shown.first?.1, false)
    }

    func testSearchRule() {
        let sureChat = RouteResult(intent: .openChat(appID: "slack", target: "Prakash", text: nil), confidence: 0.95, tier: .rules, ms: 0)
        let unsureChat = RouteResult(intent: .openChat(appID: "slack", target: "Prakash", text: nil), confidence: 0.5, tier: .rules, ms: 0)
        let app = RouteResult(intent: .openApp(appID: "slack"), confidence: 0.65, tier: .rules, ms: 0)
        let garbled = RouteResult(intent: .openChat(appID: "slack", target: "Slack", text: nil), confidence: 0.2, tier: .fuzzy, ms: 0)
        XCTAssertFalse(CommandPipeline.needsAppSearch("Slack Prakash", sureChat, appID: "slack"))
        XCTAssertTrue(CommandPipeline.needsAppSearch("Slack Prakash", unsureChat, appID: "slack"))
        XCTAssertTrue(CommandPipeline.needsAppSearch("Slack Ravi", app, appID: "slack"), "unknown name: openApp of the named app")
        XCTAssertFalse(CommandPipeline.needsAppSearch("Slack Ravi", app, appID: "messages"), "a different app than the words name")
        XCTAssertFalse(CommandPipeline.needsAppSearch("Slack me running late", app, appID: "slack"))
        XCTAssertFalse(CommandPipeline.needsAppSearch("happening click on tab in Chrome Home X", garbled, appID: "slack"))
        XCTAssertFalse(CommandPipeline.needsAppSearch("open my own chat in Slack", unsureChat, appID: "slack"))
    }
}

final class ReviewFixTests: XCTestCase {
    func testUnknownNameWithMeInTheMessageStillSearches() async {
        let finder = FakeNames()
        finder.found = [NameEntry(appID: "slack", name: "Ravi Kumar", source: .search)]
        let unsure = RouteResult(intent: .openChat(appID: "slack", target: "Ravi", text: "call me later"), confidence: 0.5,
                                 tier: .rules, ms: 0, why: "unknown name")
        let engine = TextEngine()
        engine.text = "Slack Ravi call me later"
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: unsure), actions: DryRunner(), names: finder,
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        p.heardName = { _, _ in ("Ravi", "slack") }
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(finder.searches.count, 1)
        XCTAssertNotNil(r.stages["names"])
    }

    func testNamesSelfLooksOnlyAtTheNamePart() {
        XCTAssertTrue(CommandPipeline.namesSelf("Slack me running late"))
        XCTAssertTrue(CommandPipeline.namesSelf("Slack me, running late"))
        XCTAssertTrue(CommandPipeline.namesSelf("open my own chat in Slack"))
        XCTAssertFalse(CommandPipeline.namesSelf("Slack Ravi call me later"))
        XCTAssertFalse(CommandPipeline.namesSelf("Slack Ravi, call me later"))
    }

    func testWarmerReadsOnlyWithAccessibility() async {
        var reads = 0
        var trusted = false
        let w = NameWarmer(interval: 3600, trusted: { trusted }, refresh: { reads += 1 })
        let first = await w.tick()
        XCTAssertFalse(first)
        XCTAssertEqual(reads, 0)
        trusted = true
        let second = await w.tick()
        XCTAssertTrue(second)
        XCTAssertEqual(reads, 1)
    }

    func testWarmerReadsAtStart() async throws {
        let done = expectation(description: "first read")
        let w = NameWarmer(interval: 3600, trusted: { true }, refresh: { done.fulfill() })
        w.start()
        await fulfillment(of: [done], timeout: 2)
        w.stop()
    }
}

final class EndToEndRouterTests: XCTestCase {
    /// The first live test, with the T2 fix (PR #20): no comma, a self entry, the real CommandRouter.
    func testSlackMeRunningLateOpensTheOwnChatWithTheText() async {
        let finder = FakeNames()
        let engine = TextEngine()
        engine.text = "Slack me running late."
        let runner = DryRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: finder,
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertTrue(finder.searches.isEmpty, "\(finder.searches)")
        guard case .openChat(let app, let target, let text)? = runner.runs.first?.0 else { return XCTFail("\(runner.runs)") }
        XCTAssertEqual(app, "slack")
        XCTAssertEqual(target, "Divyekant Gupta")
        XCTAssertEqual(text?.lowercased().trimmingCharacters(in: .punctuationCharacters), "running late")
    }
}

final class SlowScreenRunner: CommandActions {
    func screen() async -> ScreenSnapshot? {
        try? await Task.sleep(nanoseconds: 60_000_000)
        return nil
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        ActionOutcome(ok: true, note: "dry run")
    }
}

final class ParallelContextTests: XCTestCase {
    func testNamesAndScreenRunSideBySide() async {
        let engine = TextEngine()
        engine.text = "open notes"
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: SlowScreenRunner(), names: FakeNames(),
                                apps: { Fixture.apps },
                                allNames: { try? await Task.sleep(nanoseconds: 60_000_000); return Fixture.names },
                                frontBundleID: { nil })
        let r = await p.finish(mode: .hold)
        let names = r.stages["names"] ?? 0, screen = r.stages["screen"] ?? 0, context = r.stages["context"] ?? 0
        XCTAssertGreaterThan(names, 50)
        XCTAssertGreaterThan(screen, 50)
        XCTAssertLessThan(context, names + screen - 30, "names \(names), screen \(screen), context \(context)")
    }
}

final class StartUpTests: XCTestCase {
    func testCatalogueRefreshRunsOnceWithAccessibility() async {
        var refreshes = 0, names = 0
        await AppController.startUp(trusted: { true }, refreshCatalogue: { refreshes += 1 }, startNames: { names += 1 })
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(names, 1)
    }

    func testNoCatalogueRefreshWithoutAccessibility() async {
        var refreshes = 0, names = 0
        await AppController.startUp(trusted: { false }, refreshCatalogue: { refreshes += 1 }, startNames: { names += 1 })
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(names, 1, "the name warmer starts anyway; it waits for Accessibility itself")
    }

    func testRefreshErrorIsOnlyLogged() async {
        var names = 0
        await AppController.startUp(trusted: { true }, refreshCatalogue: { throw DiscoveryError.accessibilityOff },
                                    startNames: { names += 1 })
        XCTAssertEqual(names, 1)
    }
}

final class ScreenSummaryTests: XCTestCase {
    func testSummaryHasHostButNoPath() {
        let s = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "x", url: "https://en.wikipedia.org/wiki/Secret?q=1",
                               elements: [ScreenElement(id: "e1", role: "AXLink", label: "Log in", risky: false)])
        let line = CommandPipeline.screenSummary(s, front: "com.google.Chrome")
        XCTAssertEqual(line, "screen: com.google.Chrome en.wikipedia.org, 1 elements")
        XCTAssertFalse(line.contains("Secret"))
    }

    func testSensitivePageShowsOnlySensitive() {
        let s = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "x", url: "https://account.example.com/signin",
                               elements: [ScreenElement(id: "e1", role: "AXTextField", label: "Password", risky: false)])
        XCTAssertEqual(CommandPipeline.screenSummary(s, front: nil), "screen: com.google.Chrome, sensitive")
    }

    func testMissLogsConfidenceAndAlternatives() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let unsure = RouteResult(intent: .openApp(appID: "notes"), confidence: 0.3, tier: .rules, ms: 0, why: "two apps match",
                                 alternatives: [.openApp(appID: "slack")])
        let engine = TextEngine()
        engine.text = "open no"
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: unsure), actions: DryRunner(), names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.apple.Notes" })
        p.log = ActivityLog(store: Store(folder: folder))
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.note.contains("screen: none, front com.apple.Notes"), r.note)
        XCTAssertTrue(r.note.contains("confidence 0.30"), r.note)
        XCTAssertTrue(r.note.contains("considered:"), r.note)
    }
}


final class SearchOnlyForANamedAppTests: XCTestCase {
    /// Live test: no chat app was named, the router's weak guess was Slack, and a 5 s search ran in Slack.
    func testNoSearchWhenTheWordsNameNoApp() async {
        let finder = FakeNames()
        let weak = RouteResult(intent: .openChat(appID: "slack", target: "Slack", text: nil), confidence: 0.5, tier: .fuzzy, ms: 0)
        let engine = TextEngine()
        engine.text = "happening click on tab in Chrome Home X"
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: weak), actions: DryRunner(), names: finder,
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        p.heardName = { _, _ in ("happening", nil) }
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(finder.searches.isEmpty, "\(finder.searches)")
    }
}

final class MessageWithNoAppTests: XCTestCase {
    func testMessageRaviWithNoAppDoesNotSearch() async {
        let finder = FakeNames()
        let unsure = RouteResult(intent: .openChat(appID: "messages", target: "Ravi", text: nil), confidence: 0.5, tier: .rules, ms: 0)
        let engine = TextEngine()
        engine.text = "message Ravi"
        let p = CommandPipeline(engine: engine, router: FixedRouter(result: unsure), actions: DryRunner(), names: finder,
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        p.heardName = { _, _ in ("Ravi", nil) }
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(finder.searches.isEmpty)
    }
}

final class TimedEngine: SpeechEngine, SpeechTimingReporting {
    let id = "apple"
    var reason = "auto: Apple"
    var lastTiming: SpeechTiming?
    var onPartial: (@Sendable (String) -> Void)?
    func prepare() async throws {}
    func begin() throws {}
    func end() async throws -> Utterance {
        var t = SpeechTiming(engine: "apple", why: reason)
        t.audioMs = 1840; t.tailMs = 102; t.waitMs = 3; t.decodeMs = 41; t.totalMs = 146
        lastTiming = t
        return Utterance(text: "open notes", engine: id, ms: 146)
    }
}

final class SpeechTimingTests: XCTestCase {
    func testSpeechStagesGoToTheRecord() async {
        let p = CommandPipeline(engine: TimedEngine(), router: CommandRouter(), actions: DryRunner(), names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        p.log = ActivityLog(store: Store(folder: folder))
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(r.stages["speech.tail"], 102)
        XCTAssertEqual(r.stages["speech.wait"], 3)
        XCTAssertEqual(r.stages["speech.decode"], 41)
        XCTAssertEqual(r.stages["speech.audio"], 1840)
        XCTAssertTrue(r.note.contains("speech: apple (auto: Apple) audio 1840 ms"), r.note)
    }
}
