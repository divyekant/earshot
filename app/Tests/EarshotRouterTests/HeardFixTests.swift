import EarshotCore
import Foundation
@testable import EarshotRouter
import XCTest

/// Misheard names (gap item 12, I-15): the owner's answer teaches earshot the words that speech wrote for a label.
/// Made-up names only. The heard words come from the kinds of errors in the owner's log of 2026-11-02 and 03
/// (docs/experiments/E8-misheard-names.md).
final class HeardFixTests: XCTestCase {
    private let names = Fixtures.names + [NameEntry(appID: "slack", name: "Siobhan Kelly", source: .sidebar)]
    private var context: RouteContext { RouteContext(apps: Fixtures.apps, names: names) }
    private let siobhan = "chat:slack:siobhan kelly"
    private let at = Date(timeIntervalSince1970: 1_000)

    private func router(_ fixes: HeardFixes?) -> CommandRouter {
        var r = CommandRouter()
        r.heardFixes = fixes
        return r
    }

    private func fixes(_ entries: HeardFixes.Entry...) -> HeardFixes {
        let f = HeardFixes()
        for e in entries { f.record(e) }
        return f
    }

    // The test set of I-15: the words that speech wrote, and the label. Only the target words go in the pair.
    func testHeardWordsPairs() {
        let cases: [(String, String, String?, String?)] = [
            ("ping Shivan Kelly, running late", "Siobhan Kelly", "shivan kelly", "siobhan kelly"),
            ("Open Cloud.", "Claude", "cloud", "claude"),
            ("click on chart.", "Chat", "chart", "chat"),
            ("Open SPL Guru tab.", "FPL Guru — AI Fantasy Premier League", "spl guru", "fpl guru"),
            ("tap on reduce ear short memory use", "Reduce earshot memory use — Needs attention", "reduce ear short",
             "reduce earshot"),
            ("click project", "Projects", "project", "projects"),
            // The owner said the label: nothing was misheard.
            ("ping Nadia Brook, running late", "Nadia Brook", nil, nil),
            ("open projects tab", "Projects", nil, nil),
            // No word is near the label: the owner chose the target for another reason.
            ("message Ravi, running late", "Felix", nil, nil),
            ("click zorbex", "Reports", nil, nil),
        ]
        for (text, label, heard, want) in cases {
            let pair = CommandRouter.heardWords(text, label: label)
            XCTAssertEqual(pair?.heard, heard, text)
            XCTAssertEqual(pair?.label, want, text)
        }
    }

    // The message text never goes into the pair.
    func testPairHoldsNoMessageText() {
        let pair = CommandRouter.heardWords("ping Shivan Kelly, the server is down again", label: "Siobhan Kelly")
        XCTAssertEqual(pair?.heard, "shivan kelly")
    }

    func testReplacingKeepsTheComma() {
        XCTAssertEqual(CommandRouter.replacing("ping Shivan Kelly, running late", heard: ["shivan", "kelly"], with: "siobhan kelly"),
                       "ping siobhan kelly, running late")
        XCTAssertEqual(CommandRouter.replacing("Open Cloud.", heard: ["cloud"], with: "claude"), "Open claude.")
        XCTAssertNil(CommandRouter.replacing("open the cn/ui tab", heard: ["cn"], with: "fpl"))
        XCTAssertNil(CommandRouter.replacing("open notes", heard: ["cloud"], with: "claude"))
    }

    func testNoFixLeavesTheRouteUnsure() async {
        let r = await router(HeardFixes()).route("ping Shivan Kelly, running late", context: context)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, r.why)
    }

    // The owner's answer corrects the same words the next time, with the message text of the new command.
    func testFixMakesTheRouteSure() async {
        let f = fixes(HeardFixes.Entry(heard: "shivan kelly", label: "siobhan kelly", key: siobhan, at: at))
        let r = await router(f).route("ping Shivan Kelly, see you at noon", context: context)
        XCTAssertEqual(r.intent, .openChat(appID: "slack", target: "Siobhan Kelly", text: "see you at noon"), r.why)
        XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence)
        // Never the tier .rules: the press rules stay strict.
        XCTAssertEqual(r.tier, .fuzzy)
        XCTAssertTrue(r.why.hasSuffix("(your answer)"), r.why)
    }

    func testSendAfterStaysWithTheFix() async {
        let f = fixes(HeardFixes.Entry(heard: "shivan kelly", label: "siobhan kelly", key: siobhan, at: at))
        let r = await router(f).route("ping Shivan Kelly, running late and send", context: context)
        XCTAssertEqual(r.intent, .openChat(appID: "slack", target: "Siobhan Kelly", text: "running late"), r.why)
        XCTAssertTrue(r.sendAfter)
    }

    // The fix counts only for a sure route to the same target. The name is now only in Messages: no fix.
    func testFixNeedsTheSameTarget() async {
        let moved = Fixtures.names + [NameEntry(appID: "messages", name: "Siobhan Kelly", source: .sidebar)]
        let f = fixes(HeardFixes.Entry(heard: "shivan kelly", label: "siobhan kelly", key: siobhan, at: at))
        let r = await router(f).route("ping Shivan Kelly, running late", context: RouteContext(apps: Fixtures.apps, names: moved))
        XCTAssertFalse(r.why.contains("your answer"), r.why)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, r.why)
    }

    // A fix never changes a sure route.
    func testFixNeverChangesASureRoute() async {
        let f = fixes(HeardFixes.Entry(heard: "felix", label: "siobhan kelly", key: siobhan, at: at))
        let r = await router(f).route("message Felix, see you", context: context)
        XCTAssertEqual(r.why, "name match")
        if case .openChat(_, let target, _) = r.intent { XCTAssertEqual(target, "Felix") } else { XCTFail("\(r.intent)") }
    }

    // A screen label: the fix counts only if the label is on the screen of the same app now.
    func testFixOnScreenLabel() async {
        let page = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Page", elements: [
            Fixtures.el("e1", "AXButton", "Reports", y: 10),
            Fixtures.el("e2", "AXButton", "Inbox", y: 40),
        ])
        let key = "click:com.google.Chrome:AXButton:reports"
        let f = fixes(HeardFixes.Entry(heard: "zorbex", label: "reports", key: key, at: at))
        let ctx = RouteContext(apps: Fixtures.apps, names: names, frontBundleID: "com.google.Chrome", screen: page)
        let r = await router(f).route("click zorbex", context: ctx)
        XCTAssertEqual(r.intent, .click(elementID: "e1"), r.why)
        XCTAssertEqual(r.tier, .fuzzy)

        // The same label in another app has another key: no fix.
        var other = page
        other.bundleID = "com.apple.Notes"
        let r2 = await router(f).route("click zorbex", context: RouteContext(apps: Fixtures.apps, names: names, screen: other))
        XCTAssertNotEqual(r2.intent, .click(elementID: "e1"), r2.why)
        // The label is not on the screen: no fix.
        let gone = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Page", elements: [Fixtures.el("e2", "AXButton", "Inbox", y: 40)])
        let r3 = await router(f).route("click zorbex", context: RouteContext(apps: Fixtures.apps, names: names, screen: gone))
        XCTAssertFalse(r3.why.contains("your answer"), r3.why)
    }

    // A fix never leads to a send or a risky label (R-NV-5): "signed" for "send" is never kept.
    func testNoRiskyFix() {
        let f = HeardFixes()
        f.record(HeardFixes.Entry(heard: "signed", label: "send", key: "click:com.apple.MobileSMS:AXButton:send", at: at))
        f.record(HeardFixes.Entry(heard: "the leet", label: "delete", key: "click:com.google.Chrome:AXButton:delete", at: at))
        f.record(HeardFixes.Entry(heard: "chart", label: "chart", key: "click:a:AXButton:chart", at: at))
        f.record(HeardFixes.Entry(heard: "one two three four", label: "chat", key: "click:a:AXButton:chat", at: at))
        XCTAssertTrue(f.all.isEmpty, "\(f.all)")
    }

    func testStoreKeepsAtMostTheLimitAndReplaces() {
        var written: [HeardFixes.Entry] = []
        let f = HeardFixes(write: { written = $0 })
        for i in 0..<(HeardFixes.maxEntries + 5) {
            f.record(HeardFixes.Entry(heard: "word\(i)", label: "label", key: "app:a\(i)", at: at))
        }
        XCTAssertEqual(f.all.count, HeardFixes.maxEntries)
        XCTAssertEqual(written.count, HeardFixes.maxEntries)
        XCTAssertEqual(f.all.first?.heard, "word5")
        let before = f.all.count
        f.record(HeardFixes.Entry(heard: "word9", label: "label two", key: "app:a9", at: at))
        XCTAssertEqual(f.all.count, before)
        XCTAssertEqual(f.all.last?.label, "label two")
        XCTAssertEqual(f.matches(["open", "word9"]).first?.label, "label two")
        XCTAssertTrue(f.matches(["open", "word"]).isEmpty)
    }

    // The fix check adds almost nothing to the route (R-SP-1). Release build on CI.
    func testFixRouteTime() async {
        let f = HeardFixes()
        for i in 0..<HeardFixes.maxEntries - 1 { f.record(HeardFixes.Entry(heard: "word\(i)", label: "label", key: "app:a\(i)", at: at)) }
        f.record(HeardFixes.Entry(heard: "shivan kelly", label: "siobhan kelly", key: siobhan, at: at))
        let r = router(f)
        var times: [Double] = []
        for _ in 0..<50 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = await r.route("ping Shivan Kelly, running late", context: context)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        times.sort()
        print(String(format: "heard fix route: median %.2f ms, max %.2f ms", times[25], times[49]))
        XCTAssertLessThan(times[25], 50)
    }
}
