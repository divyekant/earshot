@testable import EarshotApp
import EarshotCore
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
}
