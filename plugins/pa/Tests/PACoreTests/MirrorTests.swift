import Foundation
import XCTest
@testable import PACore

/// A fake Apple Reminders for the tests.
final class FakeReminders: ReminderStore {
    var access: ReminderAccess
    var answer: ReminderAccess = .allowed
    var lists: [String: String] = [:]          // id to name
    var items: [String: (list: String, rec: ReminderRecord)] = [:]
    var onChange: (() -> Void)?
    var n = 0
    var failFetch = false

    init(access: ReminderAccess = .allowed) { self.access = access }

    func requestAccess(_ done: @escaping (ReminderAccess) -> Void) { access = answer; done(answer) }
    func ensureList(named: String, knownID: String?) throws -> String {
        if let k = knownID, lists[k] != nil { return k }
        if let hit = lists.first(where: { $0.value == named }) { return hit.key }
        n += 1; let id = "L\(n)"; lists[id] = named; return id
    }
    func reminders(list: String) throws -> [ReminderRecord] {
        if failFetch { throw NSError(domain: "fake", code: 1) }
        return items.values.filter { $0.list == list }.map(\.rec)
    }
    func save(_ r: ReminderRecord, list: String) throws -> String {
        var rec = r
        if rec.id == nil { n += 1; rec.id = "R\(n)" }
        rec.modifiedAt = Date()
        items[rec.id!] = (list, rec)
        return rec.id!
    }
    func remove(id: String) throws { items[id] = nil }
    func removeList(id: String) throws { lists[id] = nil; items = items.filter { $0.value.list != id } }

    /// A change by the owner in the Reminders app.
    func edit(_ id: String, at: Date, _ change: (inout ReminderRecord) -> Void) {
        var rec = items[id]!.rec
        change(&rec)
        rec.modifiedAt = at
        items[id] = (items[id]!.list, rec)
    }
}

/// The copy in Apple Reminders with a fake store (build spec 11.3). Made-up items only.
final class MirrorTests: XCTestCase {
    func setup(_ fake: FakeReminders) -> (Engine, MemoryOutput, FixedClock) {
        let (e, out, clock) = makeEngine(reminders: fake)
        e.handle(.hello(contract: 1))
        _ = out.take()
        return (e, out, clock)
    }

    func say(_ e: Engine, _ lead: String, _ text: String) {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
    }

    func testPushNewChangedDoneDropped() {
        let fake = FakeReminders()
        let (e, _, _) = setup(fake)
        say(e, "new project", "kitchen")
        say(e, "remind me", "to call the plumber at 5")
        say(e, "todo", "order the paint for kitchen by Friday")
        say(e, "note", "the landlord wants two months notice")
        XCTAssertEqual(fake.lists.values.sorted(), ["earshot"])
        let recs = fake.items.values.map(\.rec).sorted { $0.title < $1.title }
        XCTAssertEqual(recs.map(\.title), ["call the plumber", "order the paint"])
        XCTAssertEqual(recs[0].dueClock, ClockTime(17, 0))
        XCTAssertEqual(recs[0].alarm, wed(17))
        XCTAssertEqual(recs[1].dueDay, Day(2026, 11, 13))
        XCTAssertNil(recs[1].dueClock)
        XCTAssertEqual(recs[1].notes, "Project: Kitchen")
        say(e, "done", "plumber")
        XCTAssertEqual(fake.items.values.first { $0.rec.title == "call the plumber" }?.rec.completed, true)
        say(e, "drop", "paint")
        XCTAssertNil(fake.items.values.first { $0.rec.title == "order the paint" })
    }

    func testPullTickChangeDeleteAndNew() {
        let fake = FakeReminders()
        let (e, _, clock) = setup(fake)
        say(e, "remind me", "to call the plumber at 5")
        say(e, "todo", "fix the gate")
        let plumber = fake.items.first { $0.value.rec.title == "call the plumber" }!.key
        let gate = fake.items.first { $0.value.rec.title == "fix the gate" }!.key
        clock.advance(minutes: 1)
        fake.edit(plumber, at: clock.now) { $0.completed = true }
        fake.edit(gate, at: clock.now) { $0.title = "fix the garden gate"; $0.dueDay = Day(2026, 11, 14) }
        fake.onChange?()
        let items = e.store!.items(where: "1")
        XCTAssertEqual(items[0].state, .done)
        XCTAssertEqual(items[1].title, "fix the garden gate")
        XCTAssertEqual(items[1].dueOn, Day(2026, 11, 14))
        // A reminder deleted in the app drops the item.
        try? fake.remove(id: gate)
        fake.onChange?()
        XCTAssertEqual(e.store!.item(items[1].id)?.state, .dropped)
        // A reminder added on the iPhone is a new item.
        _ = try? fake.save(ReminderRecord(title: "buy stamps", dueDay: Day(2026, 11, 12), dueClock: ClockTime(10, 0)), list: "L1")
        fake.onChange?()
        let new = e.store!.openItems().first { $0.title == "buy stamps" }
        XCTAssertEqual(new?.kind, .reminder)
        XCTAssertEqual(new?.remindAt, Day(2026, 11, 12).date(e.clock.calendar, hour: 10))
        // No loop: a second pull changes nothing.
        let before = e.store!.eventCounts(since: .distantPast)
        fake.onChange?()
        XCTAssertEqual(e.store!.eventCounts(since: .distantPast), before)
    }

    func testBothChangedNewerWins() {
        let fake = FakeReminders()
        let (e, _, clock) = setup(fake)
        say(e, "todo", "fix the gate")
        let rid = fake.items.keys.first!
        // The app change is older than the PA change: the PA wins.
        let appTime = clock.now.addingTimeInterval(30)
        clock.advance(minutes: 2)
        var it = e.store!.openItems()[0]
        it.title = "fix the side gate"; it.updatedAt = clock.now
        try? e.store!.update(it, event: "test", at: clock.now)
        fake.edit(rid, at: appTime) { $0.title = "fix the front gate" }
        e.pull()
        XCTAssertEqual(fake.items[rid]?.rec.title, "fix the side gate")
        XCTAssertEqual(e.store!.item(it.id)?.title, "fix the side gate")
    }

    func testDeniedAccessAndFetchError() {
        let fake = FakeReminders(access: .notAsked)
        fake.answer = .denied
        let (e, out, _) = makeEngine(reminders: fake)
        e.handle(.hello(contract: 1))
        XCTAssertTrue(out.take().contains { $0.text == Engine.deniedNote })
        say(e, "todo", "fix the gate")
        XCTAssertTrue(fake.items.isEmpty)
        // A failed read never drops items.
        let ok = FakeReminders()
        let (e2, _, _) = setup(ok)
        say(e2, "todo", "fix the gate")
        ok.failFetch = true
        e2.pull()
        XCTAssertEqual(e2.store!.openItems().count, 1)
    }

    func testCopyOffRemovesTheList() throws {
        let fake = FakeReminders()
        let (e, _, _) = setup(fake)
        say(e, "todo", "fix the gate")
        XCTAssertEqual(fake.lists.count, 1)
        var s = e.settings
        s.reminders.copy = false
        try s.write(e.settingsURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: e.settingsURL.path)
        e.tick()
        XCTAssertTrue(fake.lists.isEmpty)
        XCTAssertTrue(e.store!.mirrors().isEmpty)
        XCTAssertEqual(e.store!.openItems().count, 1)
    }

    func testRemindersGiveTheAlert() {
        let fake = FakeReminders()
        let (e, out, clock) = setup(fake)
        say(e, "remind me", "to call the plumber at 11")
        clock.now = wed(11, 1); e.tick()
        XCTAssertTrue(out.take().filter { $0.kind == .alert }.isEmpty)
        // "done" with no words still finds the item of the alert.
        e.handle(.command(id: "d", lead: "done", text: "", context: [:]))
        XCTAssertEqual(out.take().last?.text, "Done · call the plumber")
    }
}
