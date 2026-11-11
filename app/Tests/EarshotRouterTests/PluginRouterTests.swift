import EarshotCore
@testable import EarshotRouter
import XCTest

/// A tier 2 that keeps each question. Plugin words must never reach it.
final class SpyChooser: Tier2Chooser {
    var asked: [String] = []
    func choose(_ text: String, options: [String], budgetMs: Int) async -> Int? { asked.append(text); return 0 }
}

/// The plugin lead rule (R-PL-2, R-PL-4). Made-up leads and text only.
final class PluginRouterTests: XCTestCase {
    let leads = [
        PluginLead(pluginID: "pa", lead: "remind me to"),
        PluginLead(pluginID: "pa", lead: "remind me"),
        PluginLead(pluginID: "pa", lead: "what is due"),
        PluginLead(pluginID: "pa", lead: "note"),
    ]

    private func context(_ plugins: [PluginLead]? = nil) -> RouteContext {
        RouteContext(apps: Fixtures.apps, names: Fixtures.names, plugins: plugins ?? leads)
    }

    private func route(_ text: String, _ plugins: [PluginLead]? = nil) async -> RouteResult {
        await CommandRouter().route(text, context: context(plugins))
    }

    func testLeadGivesTheRestAsText() async {
        let r = await route("Remind me to call the plumber at 5.")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "remind me to", text: "call the plumber at 5"))
        XCTAssertEqual(r.tier, .rules)
        XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence)
    }

    func testLongestLeadWins() async {
        let r = await route("remind me to water the plants")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "remind me to", text: "water the plants"))
        let short = await route("remind me tomorrow about the fern")
        XCTAssertEqual(short.intent, .handOff(pluginID: "pa", lead: "remind me", text: "tomorrow about the fern"))
    }

    func testLeadWithNoRest() async {
        let r = await route("What is due?")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "what is due", text: ""))
    }

    func testFillersBeforeTheLead() async {
        let r = await route("Hey, can you remind me to buy bread")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "remind me to", text: "buy bread"))
    }

    /// "remind me to open Slack" must not open Slack: the words after the lead are text.
    func testCommandWordsAfterTheLeadAreText() async {
        let r = await route("remind me to open Slack and message the team")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "remind me to", text: "open Slack and message the team"))
        XCTAssertEqual(CommandRouter.steps("remind me to open Slack and message the team", context: context()).count, 1,
                       "a plugin lead is never cut into a chain")
    }

    /// A trailing "and send" is text for the plugin. It never becomes a send (R-NV-5).
    func testTrailingSendIsNotASend() async {
        let r = await route("note buy stamps and send")
        XCTAssertEqual(r.intent, .handOff(pluginID: "pa", lead: "note", text: "buy stamps and send"))
        XCTAssertFalse(r.sendAfter)
    }

    /// With no plugin, nothing changes.
    func testNoPluginsNoChange() async {
        let r = await route("remind me to call the plumber", [])
        if case .handOff = r.intent { XCTFail("no plugin runs") }
        let open = await route("open Slack")
        XCTAssertEqual(open.intent, .openApp(appID: "slack"))
    }

    /// A core command wins (R-PL-4): a lead that starts with a core word or an app name is not used.
    func testCoreCommandWins() async {
        let bad = [
            PluginLead(pluginID: "bad", lead: "open"),
            PluginLead(pluginID: "bad", lead: "send"),
            PluginLead(pluginID: "bad", lead: "slack"),
            PluginLead(pluginID: "bad", lead: "type"),
            PluginLead(pluginID: "bad", lead: "notes for"),
        ]
        for l in bad { XCTAssertNotNil(PluginRouter.refusal(l.lead, apps: Fixtures.apps), l.lead) }
        let r = await route("open Slack", bad)
        XCTAssertEqual(r.intent, .openApp(appID: "slack"))
        let s = await route("send", bad)
        XCTAssertEqual(s.intent, .send)
        let n = await route("notes for today", bad)
        if case .handOff = n.intent { XCTFail("an app name lead is never used") }
    }

    func testRefusalReasons() {
        XCTAssertNil(PluginRouter.refusal("remind me to", apps: Fixtures.apps))
        XCTAssertNil(PluginRouter.refusal("note", apps: Fixtures.apps), "note is not the app Notes")
        XCTAssertNotNil(PluginRouter.refusal("", apps: Fixtures.apps))
        XCTAssertNotNil(PluginRouter.refusal("please remind me", apps: Fixtures.apps), "a filler first word")
        XCTAssertNotNil(PluginRouter.refusal("one two three four five six", apps: Fixtures.apps), "too many words")
        XCTAssertNotNil(PluginRouter.refusal("click here", apps: Fixtures.apps))
    }

    /// Two plugins with the same lead: the first id keeps it.
    func testSameLeadFirstIDWins() {
        let two = [PluginLead(pluginID: "zeta", lead: "note"), PluginLead(pluginID: "alpha", lead: "note")]
        XCTAssertEqual(PluginRouter.match("note milk", plugins: two, apps: [])?.lead.pluginID, "alpha")
    }

    /// The lead counts as a command, so an armed "type" does not type the words of a plugin command.
    func testLeadIsACommandForDictation() {
        XCTAssertTrue(CommandRouter.startsWithCommand("remind me to call", context: context()))
        XCTAssertTrue(CommandRouter.hasCommandWord("note buy stamps", context: context()))
        XCTAssertFalse(CommandRouter.hasCommandWord("note buy stamps", context: context([])))
    }

    /// A lead must match whole words: "noted" is not "note".
    func testWholeWordsOnly() {
        XCTAssertNil(PluginRouter.match("noted the stamps", plugins: leads, apps: []))
    }

    /// The match runs on each command, so it must stay fast (R-SP-1). 1,000 matches with 4 leads.
    func testMatchIsFast() {
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<1000 { _ = PluginRouter.match("open the second result on the page", plugins: leads, apps: Fixtures.apps) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000 / 1000
        print("plugin lead match: \(String(format: "%.4f", ms)) ms each")
        XCTAssertLessThan(ms, 1.0)
    }

    /// The words after a plugin lead never go to Jev (R-MD-1, D-9): the lead rule is sure, so tier 2 does not run.
    func testPluginWordsNeverReachTier2() async {
        let spy = SpyChooser()
        let r = await CommandRouter(tier2: spy).route("remind me to click the blue thing maybe", context: context())
        XCTAssertEqual(r.tier, .rules)
        XCTAssertTrue(spy.asked.isEmpty, "\(spy.asked)")
    }
}
