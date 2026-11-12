import Foundation
import XCTest
@testable import PACore

/// The clock with a fake time (build spec 10, go mark "Alert time"). Made-up items only.
final class ClockTests: XCTestCase {
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        return out.take().last!
    }

    func alerts(_ out: MemoryOutput) -> [String] { out.take().filter { $0.kind == .alert }.map(\.text) }

    func at(_ e: Engine, _ clock: FixedClock, _ date: Date) { clock.now = date; e.tick() }

    func testAlertAtItsTimeAndRepeatOnce() {
        let (e, out, clock) = makeEngine()
        e.handle(.hello(contract: 1)); _ = out.take()
        say(e, out, "remind me", "to call the plumber at 11")
        at(e, clock, wed(10, 1))  // the pages write; then the next check is the alert
        XCTAssertEqual(e.nextCheck(), wed(11))
        at(e, clock, wed(10, 59)); XCTAssertEqual(alerts(out), [])
        at(e, clock, wed(11).addingTimeInterval(1)); XCTAssertEqual(alerts(out), ["Reminder · call the plumber"])
        at(e, clock, wed(11, 5)); XCTAssertEqual(alerts(out), [])
        at(e, clock, wed(11, 10).addingTimeInterval(1)); XCTAssertEqual(alerts(out), ["Reminder · call the plumber"])
        at(e, clock, wed(11, 30)); XCTAssertEqual(alerts(out), [])
        // After the second time, the reminder waits for the morning list.
        XCTAssertEqual(e.store!.alerts(where: "1").last?.state, .movedToList)
    }

    func testDoneAnswersTheAlert() {
        let (e, out, clock) = makeEngine()
        say(e, out, "remind me", "to call the plumber at 11")
        at(e, clock, wed(11)); _ = out.take()
        clock.now = wed(11, 2)
        XCTAssertEqual(say(e, out, "done").text, "Done · call the plumber")
        at(e, clock, wed(11, 20)); XCTAssertEqual(alerts(out), [])
    }

    func testThreeAlertsInOneHour() {
        let (e, out, clock) = makeEngine()
        for n in 1...5 { say(e, out, "remind me", "to stretch number \(n) at 11:0\(n)") }
        at(e, clock, wed(11, 10))
        XCTAssertEqual(alerts(out).count, 3)
        XCTAssertEqual(e.store!.alerts(where: "state = 'moved_to_list'").count, 2)
    }

    func testQuietHoursAndSaidClockTime() {
        let (e, out, clock) = makeEngine(now: wed(21))
        say(e, out, "remind me", "to lock the door at 23:30")
        say(e, out, "remind me", "to stretch in 90 minutes")  // 22:30: "in 90 minutes" is a clock time that the owner set.
        at(e, clock, wed(23, 31))
        XCTAssertEqual(alerts(out), ["Reminder · stretch", "Reminder · lock the door"])
        // A reminder that was moved by "snooze" into quiet hours, with no said time, waits for the morning list.
        let (e2, out2, clock2) = makeEngine(now: wed(21))
        say(e2, out2, "remind me", "to water the plants")
        var it = e2.store!.openItems()[0]
        let old = it
        it.remindAt = wed(22, 30); it.hasClock = false
        try? e2.store!.update(it, event: "test", at: wed(21))
        e2.planAlerts(it, old: old)
        at(e2, clock2, wed(22, 31))
        XCTAssertEqual(alerts(out2), [])
        XCTAssertEqual(e2.store!.alerts(where: "1").last?.state, .movedToList)
    }

    func testQuietForAndHeldList() {
        let (e, out, clock) = makeEngine()
        XCTAssertEqual(say(e, out, "quiet", "for 2 hours").text, "Quiet · until 12:00")
        say(e, out, "remind me", "to call the plumber at 11")
        at(e, clock, wed(11, 1)); XCTAssertEqual(alerts(out), [])
        clock.now = wed(12, 1); e.tick()
        let list = out.take()
        XCTAssertEqual(list.first?.text, "While quiet")
        XCTAssertEqual(list.first?.items, ["call the plumber · 11:00"])
        XCTAssertEqual(say(e, out, "quiet", "until 5").text, "Quiet · until 17:00")
        XCTAssertEqual(say(e, out, "quiet", "off").text, "Quiet is off.")
    }

    func testMorningListOnceAndAfterSleep() {
        let (e, out, clock) = makeEngine(now: wed(8))
        e.handle(.hello(contract: 1)); _ = out.take()
        say(e, out, "todo", "send the tax papers by tomorrow")
        say(e, out, "remind me", "to call the plumber at 5")
        // The Mac sleeps from 08:30 to 10:15. The list shows at the first check after the wake.
        at(e, clock, wed(10, 15))
        let lists = out.take().filter { $0.kind == .list }
        XCTAssertEqual(lists.first?.text, "Today")
        XCTAssertEqual(lists.first?.items, ["call the plumber · 17:00", "send the tax papers · tomorrow"])
        at(e, clock, wed(10, 30))
        XCTAssertTrue(out.take().filter { $0.kind == .list }.isEmpty)
    }

    func testAlertAfterSleepIsNotLate() {
        let (e, out, clock) = makeEngine()
        e.handle(.hello(contract: 1)); _ = out.take()
        say(e, out, "remind me", "to call the plumber at 11")
        // The Mac sleeps over the time. At the wake, the tick shows the alert.
        at(e, clock, wed(11, 40))
        XCTAssertEqual(alerts(out), ["Reminder · call the plumber"])
    }

    func testMissedListAtStart() {
        let folder = tempFolder()
        let clock = FixedClock(wed(10))
        let out = MemoryOutput()
        var e = Engine(folder: folder, clock: clock, output: out)
        e.start()
        e.handle(.command(id: "1", lead: "remind me", text: "to call the plumber at 11", context: [:]))
        e.stop()
        clock.now = wed(13)
        _ = out.take()
        e = Engine(folder: folder, clock: clock, output: out)
        e.start()
        e.handle(.hello(contract: 1))
        let msgs = out.take()
        XCTAssertEqual(msgs.first?.text, "Missed")
        XCTAssertEqual(msgs.first?.items, ["call the plumber · 11:00"])
        XCTAssertTrue(msgs.filter { $0.kind == .alert }.isEmpty)
    }

    func testRuleSettingOffAndList() throws {
        let (e, out, clock) = makeEngine()
        say(e, out, "remind me", "to call the plumber at 11")
        e.settings.rules.time = .list
        at(e, clock, wed(11, 1))
        XCTAssertEqual(alerts(out), [])
        XCTAssertEqual(e.store!.alerts(where: "1").first?.state, .movedToList)
    }

    func testSettingsFileChangeIsRead() throws {
        let (e, _, _) = makeEngine()
        var s = e.settings
        s.maxAlertsPerHour = 1
        try s.write(e.settingsURL)
        // The file time must change: set it one second later.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: e.settingsURL.path)
        e.tick()
        XCTAssertEqual(e.settings.maxAlertsPerHour, 1)
    }

    /// The real clock: a reminder 2 s ahead, with the timer rule of the program. Records the delay.
    func testRealTimeAlertDelay() {
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: SystemClock(), output: out)
        e.start()
        e.handle(.command(id: "1", lead: "remind me", text: "to stretch in 1 minute", context: [:]))
        // Move the alert to 2 s from now.
        let due = Date().addingTimeInterval(2)
        try? e.store!.db.run("UPDATE alert SET fire_at = ?", [.real(due.timeIntervalSince1970)])
        let q = DispatchQueue(label: "t")
        let timer = DispatchSource.makeTimerSource(queue: q)
        func schedule() {
            let next = e.nextCheck() ?? Date().addingTimeInterval(60)
            timer.schedule(wallDeadline: .now() + min(60, max(0.05, next.timeIntervalSinceNow + 0.05)))
        }
        let got = expectation(description: "alert")
        var shownAt: Date?
        timer.setEventHandler {
            e.tick()
            if shownAt == nil, out.messages.contains(where: { $0.kind == .alert }) { shownAt = Date(); got.fulfill() }
            schedule()
        }
        q.sync { schedule() }
        timer.resume()
        wait(for: [got], timeout: 10)
        timer.cancel()
        let delay = shownAt!.timeIntervalSince(due)
        print("MARK alert delay after its time: \(Int(delay * 1000)) ms")
        XCTAssertLessThan(delay, 5)
    }

    /// Silence (build spec 10.2): an open to-do with no change for 7 days, or 3 days for "waiting for", is a quiet
    /// line in the morning list. Made-up items only.
    func testSilenceGivesQuietLines() {
        let (e, out, clock) = makeEngine()
        e.handle(.hello(contract: 1)); _ = out.take()
        say(e, out, "todo", "order the tiles")
        say(e, out, "todo", "waiting for the plumber quote")
        func quiet(_ days: Double) -> [String] {
            clock.now = wed(10).addingTimeInterval(days * 86400)
            return e.morningItems(clock.now).map(\.title)
        }
        XCTAssertEqual(quiet(2.9), [])
        XCTAssertEqual(quiet(3), ["waiting for the plumber quote"])
        XCTAssertEqual(Set(quiet(7)), ["order the tiles", "waiting for the plumber quote"])
        var s = e.settings; s.rules.silence = .off; e.settings = s
        XCTAssertEqual(quiet(8), [])
    }
}

