import EarshotCore
import Foundation
@testable import EarshotRouter
import XCTest

/// The owner's last answer breaks the same tie the next time (gap item 6). Made-up names only.
final class HabitTests: XCTestCase {
    private let names = Fixtures.names + [
        NameEntry(appID: "slack", name: "Nadia Brook", source: .sidebar),
        NameEntry(appID: "messages", name: "Nadia Brook", source: .sidebar),
    ]
    private var context: RouteContext { RouteContext(apps: Fixtures.apps, names: names) }
    private let slack = "chat:slack:nadia brook", messages = "chat:messages:nadia brook"

    private func router(_ habits: TieHabits?) -> CommandRouter {
        var r = CommandRouter()
        r.habits = habits
        return r
    }

    func testTieIsUnsureWithNoHabit() async {
        let r = await router(TieHabits()).route("ping Nadia Brook, running late", context: context)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, r.why)
        XCTAssertEqual(r.why, "two chats match")
    }

    func testLastAnswerBreaksTheTie() async {
        for (chosen, other, app) in [(messages, slack, "messages"), (slack, messages, "slack")] {
            let habits = TieHabits()
            habits.record(chosen: chosen, over: [other])
            let r = await router(habits).route("ping Nadia Brook, running late", context: context)
            XCTAssertEqual(r.intent, .openChat(appID: app, target: "Nadia Brook", text: "running late"), r.why)
            XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence)
            // Never the tier .rules: the press rules stay strict.
            XCTAssertEqual(r.tier, .fuzzy)
            XCTAssertTrue(r.why.hasSuffix("your last answer"), r.why)
        }
    }

    // A newer answer for the same targets wins.
    func testTheNewestAnswerWins() async {
        let habits = TieHabits()
        habits.record(chosen: messages, over: [slack])
        habits.record(chosen: slack, over: [messages])
        XCTAssertEqual(habits.all.count, 1)
        let r = await router(habits).route("ping Nadia Brook, running late", context: context)
        if case .openChat(let app, _, _) = r.intent { XCTAssertEqual(app, "slack") } else { XCTFail("\(r.intent)") }
    }

    // The send words stay with the text of the chosen chat.
    func testSendAfterStaysWithTheChosenChat() async {
        let habits = TieHabits()
        habits.record(chosen: messages, over: [slack])
        let r = await router(habits).route("ping Nadia Brook, running late and send", context: context)
        XCTAssertEqual(r.intent, .openChat(appID: "messages", target: "Nadia Brook", text: "running late"))
        XCTAssertTrue(r.sendAfter)
    }

    // A habit never changes a sure route, and a tie with a target that the owner did not see has no habit.
    func testHabitOnlyForTheSameTie() async {
        let habits = TieHabits()
        habits.record(chosen: "chat:messages:felix", over: ["chat:slack:felix"])
        let sure = await router(habits).route("message Felix, see you", context: RouteContext(apps: Fixtures.apps, names: Fixtures.names))
        XCTAssertEqual(sure.why, "name match")

        let three = names + [NameEntry(appID: "whatsapp", name: "Nadia Brook", source: .sidebar)]
        let h2 = TieHabits()
        h2.record(chosen: messages, over: [slack])
        let r = await router(h2).route("ping Nadia Brook, running late", context: RouteContext(apps: Fixtures.apps, names: three))
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, r.why)
    }

    func testKeys() {
        let page = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Page", elements: [
            Fixtures.el("e1", "AXButton", "Reports", y: 10),
            Fixtures.el("e2", "AXButton", "Delete", y: 20),
        ])
        XCTAssertEqual(TieHabits.key(.openChat(appID: "slack", target: "Nadia Brook", text: "secret words"), screen: nil), slack)
        XCTAssertEqual(TieHabits.key(.click(elementID: "e1"), screen: page), "click:com.google.Chrome:AXButton:reports")
        // A risky element and a send have no key: a habit never makes them sure (R-NV-5).
        XCTAssertNil(TieHabits.key(.click(elementID: "e2"), screen: page))
        XCTAssertNil(TieHabits.key(.send, screen: page))
        XCTAssertNil(TieHabits.key(.typeText("hi"), screen: page))
    }

    func testStoreKeepsAtMostTheLimitAndWrites() {
        var written: [TieHabits.Entry] = []
        let habits = TieHabits(write: { written = $0 })
        for i in 0..<(TieHabits.maxEntries + 5) { habits.record(chosen: "app:a\(i)", over: ["app:b\(i)"]) }
        XCTAssertEqual(habits.all.count, TieHabits.maxEntries)
        XCTAssertEqual(written.count, TieHabits.maxEntries)
        XCTAssertEqual(habits.all.first?.chosen, "app:a5")
        // One target alone is not a tie.
        habits.record(chosen: "app:x", over: [])
        XCTAssertFalse(habits.all.contains { $0.chosen == "app:x" })
    }

    // The habit check adds almost nothing to the route (R-SP-1). Release build on CI.
    func testHabitRouteTime() async {
        let habits = TieHabits()
        for i in 0..<TieHabits.maxEntries - 1 { habits.record(chosen: "app:a\(i)", over: ["app:b\(i)"]) }
        habits.record(chosen: messages, over: [slack])
        let r = router(habits)
        var times: [Double] = []
        for _ in 0..<50 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = await r.route("ping Nadia Brook, running late", context: context)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        times.sort()
        print(String(format: "habit route: median %.2f ms, max %.2f ms", times[25], times[49]))
        XCTAssertLessThan(times[25], 50)
    }
}
