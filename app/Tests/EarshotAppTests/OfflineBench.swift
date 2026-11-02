@testable import EarshotApp
import EarshotCore
import EarshotActions
import EarshotDiscovery
import EarshotRouter
import XCTest

// The offline bench of the command path: typed text → screen → route → app search → dry-run actions.
// No speech, no app and no key press. It measures the code of earshot only. Run it with:
//   swift test --filter OfflineBench
final class OfflineBench: XCTestCase {
    static let commands = [
        "Slack me, running late", "Slack me on my way", "iMessage me, can we move the meeting", "text me sounds good",
        "Slack Prakash", "message prakash on slack", "Slack alerts", "ping alerts", "text Mrunal",
        "message mrunal on messages", "open Slack", "open notes", "switch to Chrome", "open messages",
        "Slack me, call me after lunch", "Messages me, buy milk", "go to alerts on slack", "Slack prakash iyer",
        "I think the meeting moved to Thursday", "running late, be there in ten minutes", "what is the weather like today",
        "Slack Ravi", "message Ishaan on Messages", "open my own chat in Slack", "text prakash", "Slack posthog",
        "open hn.com", "go to news dot ycombinator dot com",
    ]

    func testBench() async {
        let finder = FakeNames()
        let engine = TextEngine()
        let runner = DryRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: finder,
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        var totals: [Double] = [], routes: [Double] = []
        var acted = 0
        for _ in 0..<5 {  // 5 rounds, so that the first-call cost does not decide the median
            for c in Self.commands {
                engine.text = c
                let r = await p.finish(mode: .hold)
                totals.append(r.stages["total"] ?? 0)
                routes.append(r.stages["route"] ?? 0)
                if r.ok { acted += 1 }
            }
        }
        func pct(_ a: [Double], _ q: Double) -> Double { let s = a.sorted(); return s[min(s.count - 1, Int(Double(s.count) * q))] }
        let line = String(format: "OfflineBench: %d commands × 5. Total median %.2f ms, slowest 1 in 10 %.2f ms. Route median %.2f ms, slowest 1 in 10 %.2f ms. Acted %d of %d.",
                          Self.commands.count, pct(totals, 0.5), pct(totals, 0.9), pct(routes, 0.5), pct(routes, 0.9), acted, totals.count)
        print(line)
        XCTAssertLessThan(pct(totals, 0.9), 50, "the command path without speech and apps must stay fast")
    }

    /// Menu commands (R-MT-1): the same path with 70 screen elements and 250 menu items of the front app, from the cache.
    func testMenuBench() async {
        var items = [MenuItem(path: ["Edit", "Undo"], enabled: true), MenuItem(path: ["Edit", "Copy"], enabled: true),
                     MenuItem(path: ["Edit", "Paste"], enabled: true), MenuItem(path: ["Edit", "Select All"], enabled: true),
                     MenuItem(path: ["File", "New Note"], enabled: true), MenuItem(path: ["View", "Show Sidebar"], enabled: true)]
        for m in 0..<10 { for k in 0..<24 { items.append(MenuItem(path: ["Menu \(m)", "Command \(m) \(k) item"], enabled: true)) } }
        let menu = MenuCache.elements(items)
        let page = (0..<70).map { ScreenElement(id: "e\($0)", role: "AXLink", label: "Story number \($0) title", risky: false, y: Double($0)) }
        final class PageRunner: CommandActions {
            let page: [ScreenElement]
            init(_ page: [ScreenElement]) { self.page = page }
            func screen() async -> ScreenSnapshot? { ScreenSnapshot(bundleID: "com.apple.Notes", windowTitle: "t", elements: page) }
            func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome { ActionOutcome(ok: true, note: "dry run") }
        }
        let engine = TextEngine()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: PageRunner(page), names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.apple.Notes" })
        p.menus = { _ in menu }
        let commands = ["select all", "undo", "copy", "paste", "new note", "show sidebar", "click story number 5 title",
                        "Slack me, running late", "open hn.com", "what is the weather like today"]
        var totals: [Double] = [], routes: [Double] = []
        for _ in 0..<5 {
            for c in commands {
                engine.text = c
                let r = await p.finish(mode: .hold)
                totals.append(r.stages["total"] ?? 0)
                routes.append(r.stages["route"] ?? 0)
            }
        }
        func pct(_ a: [Double], _ q: Double) -> Double { let s = a.sorted(); return s[min(s.count - 1, Int(Double(s.count) * q))] }
        print(String(format: "MenuBench: %d commands × 5, %d menu items + 70 elements. Total median %.2f ms, slowest 1 in 10 %.2f ms. Route median %.2f ms, slowest 1 in 10 %.2f ms.",
                     commands.count, menu.count, pct(totals, 0.5), pct(totals, 0.9), pct(routes, 0.5), pct(routes, 0.9)))
        // The debug build scores labels about 15 times slower than the release build (the app bundle is release).
        // Release: route median 5.7 ms, slowest 1 in 10 11.5 ms. The router budget is 300 ms (R-SP-2).
        #if DEBUG
        let limit = 300.0
        #else
        let limit = 50.0
        #endif
        XCTAssertLessThan(pct(totals, 0.9), limit, "menu items must not slow the command path")
    }
}
