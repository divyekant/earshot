import Foundation
import XCTest
@testable import PACore

/// Phase 3, package S3: the calendar, links by the owner and by a rule, and the near-event alert. Made-up data only.
final class CalendarTests: XCTestCase {
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        return out.take().last!
    }

    func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "tsv", subdirectory: "Fixtures/phase3/calendar")!
    }

    static func london() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: s)!
    }

    /// The made-up calendar of owner-calendar.tsv.
    func ownerCalendar() throws -> [CalEvent] {
        try BenchFixtures.rows(fixture("owner-calendar")).filter { $0.count >= 5 }.map { r in
            let start = Self.date(r[3])
            return CalEvent(sourceID: r[0], title: r[1], startsAt: start,
                            endsAt: start.addingTimeInterval(Double(Int(r[4]) ?? 60) * 60),
                            people: r[2].isEmpty ? [] : [r[2]])
        }
    }

    func calendarEngine() throws -> (Engine, MemoryOutput, FixedClock, FixtureCalendar) {
        let (e, out, clock) = makeEngine()
        let cal = FixtureCalendar(try ownerCalendar())
        e.calendarSource = cal
        e.readCalendar()
        return (e, out, clock, cal)
    }

    // MARK: - The read

    func testReadKeeps14DaysAndPrunes() throws {
        let (e, _, _, cal) = try calendarEngine()
        let store = try XCTUnwrap(e.store)
        // c14 is on 5 December: more than 14 days after Wed 11 Nov.
        XCTAssertEqual(store.events(from: wed(0), to: wed(0).addingTimeInterval(30 * 86400)).count, 13)
        cal.all.removeAll { $0.sourceID == "c01" }
        e.readCalendar()
        XCTAssertFalse(store.events(from: wed(0), to: wed(0).addingTimeInterval(30 * 86400)).contains { $0.sourceID == "c01" })
        // Off: the PA forgets the events.
        var s = e.settings
        let old = s
        s.sources.calendar = false
        e.settings = s
        e.settingsChanged(from: old)
        XCTAssertEqual(store.events(from: wed(0), to: wed(0).addingTimeInterval(30 * 86400)).count, 0)
        e.readCalendar()
        XCTAssertEqual(store.events(from: wed(0), to: wed(0).addingTimeInterval(30 * 86400)).count, 0)
    }

    // MARK: - Links by the owner (9.2): 27 or more of 30 correct, 1 or fewer wrong

    func testOwnerLinksFixture() throws {
        let (e, out, _, _) = try calendarEngine()
        say(e, out, "new project", "kitchen")
        let store = try XCTUnwrap(e.store)
        let rows = try BenchFixtures.rows(fixture("owner-links")).filter { $0.count >= 3 }
        XCTAssertEqual(rows.count, 30)
        var correct = 0, wrong = 0
        var misses: [String] = []
        for r in rows {
            let before = store.items(where: "1 = 1").count
            say(e, out, r[0], r[1])
            let items = store.items(where: "1 = 1")
            XCTAssertEqual(items.count, before + 1, r[1])
            let it = items.max { $0.id < $1.id }!
            let link = try store.db.query("""
                SELECT e.source_id FROM cal_event_link l JOIN cal_event e ON e.id = l.event_id WHERE l.item_id = ?
                """, [.int(it.id)]).first?.first?.text ?? "-"
            if link == r[2] { correct += 1 } else {
                misses.append("\(r[1]) -> \(link), want \(r[2])")
                if link != "-" { wrong += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(correct, 27, misses.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(wrong, 1, misses.joined(separator: "\n"))
        print("owner links: \(correct) of 30 correct, \(wrong) wrong")
    }

    func testOwnerLinkNoteAndReminderTime() throws {
        let (e, out, _, _) = try calendarEngine()
        let note = say(e, out, "remind me", "before the dentist to bring the x-ray").text
        XCTAssertEqual(note, "Reminder · before Dentist, Thu 10:00 · bring the x-ray")
        let it = try XCTUnwrap(e.store?.items(where: "kind = 'reminder'").first)
        XCTAssertEqual(it.remindAt, Self.date("2026-11-12T09:45"))
        XCTAssertEqual(say(e, out, "todo", "print the contract for the meeting with Sam").text,
                       "To-do · for Meeting with Sam, Fri 14:00 · print the contract")
    }

    // MARK: - Links by a rule (EventLinker)

    func testLinkerLines() {
        let projects = [EventLinker.Project(key: "kitchen", name: "Kitchen"), EventLinker.Project(key: "taxes", name: "Tax year")]
        let recs: [EventLinker.Record] = [
            .init(key: "k1", project: "kitchen", title: "call Tom the plumber about the start date", order: 1),
            .init(key: "k2", project: "kitchen", title: "choose the colour of the grout", order: 2),
            .init(key: "kd", project: "kitchen", title: "quote", isDoc: true, order: 3),
            .init(key: "t1", project: "taxes", title: "send Helen the rental figures", order: 1),
        ]
        let day = Day(2026, 11, 12)
        // L2: a person of the event.
        var r = EventLinker(lines: .l2).link(title: "Call", people: ["Helen Ward"], day: day, projects: projects,
                                             records: recs, nearest: [], ruleProject: nil)
        XCTAssertEqual(r.items, ["t1"])
        // L1 needs a second signal: the name alone is not enough.
        r = EventLinker(lines: .l1).link(title: "Kitchen disco", people: [], day: day, projects: projects, records: recs,
                                         nearest: [], ruleProject: nil)
        XCTAssertTrue(r.isEmpty)
        r = EventLinker(lines: .l1).link(title: "Kitchen grout check", people: [], day: day, projects: projects, records: recs,
                                         nearest: [], ruleProject: nil)
        XCTAssertEqual(r.items, ["k2", "k1"])
        XCTAssertEqual(r.docs, ["kd"])
        r = EventLinker(lines: .l1).link(title: "Kitchen fitter", people: [], day: day, projects: projects, records: recs,
                                         nearest: ["kitchen", "kitchen", "kitchen", "taxes", nil], ruleProject: nil)
        XCTAssertFalse(r.isEmpty)
        // L3: the project rule.
        r = EventLinker(lines: .l3).link(title: "Accountant", people: [], day: day, projects: projects, records: recs,
                                         nearest: [], ruleProject: "taxes")
        XCTAssertEqual(r.items, ["t1"])
        XCTAssertEqual(EventLinker.Lines(label: "L1+L3"), [.l1, .l3])
    }

    // MARK: - The near-event alert (9.3)

    func testNearEventAlertWithLinks() throws {
        let (e, out, clock, _) = try calendarEngine()
        say(e, out, "todo", "show the budget at the team meeting")
        _ = out.take()
        // The team meeting is on Tue 17 Nov at 10:00. 15 minutes before: the alert with the list.
        clock.now = Self.date("2026-11-17T09:44")
        e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
        clock.now = Self.date("2026-11-17T09:45")
        e.tick()
        let alerts = out.take().filter { $0.kind == .alert }
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.text, "Team meeting · 10:00")
        XCTAssertEqual(alerts.first?.items, ["show the budget"])
        // One alert only.
        clock.now = Self.date("2026-11-17T09:50")
        e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
    }

    func testNoAlertWithNoLinkOrAfterTheEnd() throws {
        let (e, out, clock, _) = try calendarEngine()
        clock.now = Self.date("2026-11-12T09:50")
        e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
        // A link, but the Mac was asleep until after the end.
        say(e, out, "todo", "prepare questions for the parents evening")
        _ = out.take()
        clock.now = Self.date("2026-11-18T19:40")
        e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
    }

    func testNearEventModeOff() throws {
        let (e, out, clock, _) = try calendarEngine()
        e.settings.rules.nearEvent = .off
        say(e, out, "todo", "show the budget at the team meeting")
        _ = out.take()
        clock.now = Self.date("2026-11-17T09:45")
        e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
    }
}
