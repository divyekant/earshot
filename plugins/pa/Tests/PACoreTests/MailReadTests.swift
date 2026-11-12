import Foundation
import XCTest
@testable import PACore

/// Phase 3, package S4: the mail read plan (spec 6.1) and the bulk filter (8.1). Made-up data only.
final class MailReadTests: XCTestCase {
    let owner: Set<String> = ["maya.rao@example.com"]

    func mailbox(_ name: String) throws -> FixtureMail {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/phase3/mail"))
        return try FixtureMail(jsonl: url)
    }

    static func msg(_ id: String, minutes: Double, from: String = "sam.lee@example.net", to: [String] = ["maya.rao@example.com"],
                    replied: Bool = false, list: Bool = false) -> MailMessage {
        MailMessage(id: id, messageID: "<\(id)@x.example>", fromName: "Sam Lee", fromAddress: from, to: to, cc: [],
                    subject: "Subject \(id)", date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60),
                    listHeader: list, replied: replied, text: "Text of \(id).")
    }

    func testBulkFilterReasons() {
        let base = Self.msg("a", minutes: 0)
        XCTAssertNil(BulkFilter.reason(base, owner: owner))
        var m = base; m.junk = true
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "junk")
        m = base; m.fromAddress = "Maya.Rao@example.com"
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "from owner")
        m = base; m.listHeader = true
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "list header")
        m = base; m.precedence = "bulk"
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "precedence")
        m = base; m.autoSubmitted = true
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "automatic")
        m = base; m.to = ["someone@example.org"]
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "owner not in to or cc")
        m = base; m.cc = (1...20).map { "p\($0)@example.org" }
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "many addresses")
        m = base; m.replied = true
        XCTAssertEqual(BulkFilter.reason(m, owner: owner), "replied")
    }

    /// The filter must keep the messages with a request on the development mailbox.
    func testBulkFilterOnDevMailbox() throws {
        let box = try mailbox("dev")
        let url = try XCTUnwrap(Bundle.module.url(forResource: "dev-labels", withExtension: "tsv", subdirectory: "Fixtures/phase3/mail"))
        let wanted = Set(try BenchFixtures.rows(url).filter { $0.count >= 2 && $0[1] == "1" }.map { $0[0] })
        var passed = 0, wantedRemoved = 0
        for m in box.messages {
            let r = BulkFilter.reason(m, owner: owner)
            if r == nil { passed += 1 } else if wanted.contains(m.id) { wantedRemoved += 1 }
        }
        print("bulk filter dev: \(passed) of \(box.messages.count) pass, \(wantedRemoved) of \(wanted.count) requests removed")
        XCTAssertEqual(wanted.count, 20)
        XCTAssertEqual(wantedRemoved, 0)
        XCTAssertLessThan(passed, box.messages.count)
    }

    func testFirstReadKeepsTheBudget() throws {
        let box = try mailbox("dev")
        var plan = MailReadPlan(known: [], lastNewest: nil, owner: owner)
        let r = plan.run(box)
        XCTAssertFalse(r.unchanged)
        XCTAssertLessThanOrEqual(r.seen.count, plan.maxMessages)
        XCTAssertLessThanOrEqual(r.seen.filter(\.hasText).count, plan.maxTexts)
        XCTAssertTrue(r.seen.allSatisfy { $0.hasText == ($0.bulk == nil) })
        XCTAssertNotNil(r.newest)
        // 200 messages and a budget of 10: the read is not complete.
        XCTAssertFalse(r.complete)
        // With a first-read limit after all messages: one envelope, then the end.
        plan.since = Date(timeIntervalSince1970: 4_000_000_000)
        let r2 = plan.run(try mailbox("dev"))
        XCTAssertEqual(r2.seen.count, 1)
        XCTAssertTrue(r2.seen[0].old)
        XCTAssertTrue(r2.complete)
    }

    func testCheapCheckAndNewMessages() {
        let box = FixtureMail(messages: (1...30).map { Self.msg("m\($0)", minutes: Double($0)) })
        let known = Set(box.messages.map(\.id))
        var plan = MailReadPlan(known: known, lastNewest: "m30", owner: owner)
        var r = plan.run(box)
        XCTAssertTrue(r.unchanged)
        XCTAssertTrue(r.complete)
        XCTAssertEqual(box.calls, 1)
        // Two new messages: one list mail and one to the owner.
        box.add(Self.msg("m31", minutes: 31, list: true))
        box.add(Self.msg("m32", minutes: 32))
        r = plan.run(box)
        XCTAssertFalse(r.unchanged)
        XCTAssertEqual(r.newest, "m32")
        XCTAssertEqual(r.seen.map(\.message.id), ["m32", "m31"])
        XCTAssertEqual(r.seen.map(\.bulk), [nil, "list header"])
        XCTAssertEqual(r.seen[0].message.text, "Text of m32.")
        XCTAssertEqual(r.seen[1].message.text, "")
        XCTAssertTrue(r.complete)
        plan.lastNewest = r.newest
        plan.known.formUnion(r.seen.map(\.message.id))
        XCTAssertTrue(plan.run(box).unchanged)
    }

    func testTimeBudgetStopsTheRead() {
        let box = FixtureMail(messages: (1...20).map { Self.msg("m\($0)", minutes: Double($0)) })
        let plan = MailReadPlan(known: [], lastNewest: nil, owner: owner)
        // Each look at the clock is 1 s later: the budget of 6 s ends after a few events.
        var t = Date(timeIntervalSince1970: 0)
        let r = plan.run(box) { t = t.addingTimeInterval(1); return t }
        XCTAssertFalse(r.complete)
        XCTAssertLessThan(r.seen.count, plan.maxMessages)
        XCTAssertLessThanOrEqual(r.seconds, plan.maxSeconds + 2)
    }

    func testAnsweredFlags() {
        let box = FixtureMail(messages: [Self.msg("m1", minutes: 1, replied: true), Self.msg("m2", minutes: 2)])
        var plan = MailReadPlan(known: ["m1", "m2"], lastNewest: "m2", owner: owner)
        plan.openFlagIDs = ["m1", "m2", "gone"]
        let r = plan.run(box)
        XCTAssertEqual(r.answered, ["m1"])
    }
}

/// Phase 3, S4: the new arrival on the engine (8.7) and the read loop (6.1). Made-up data only.
final class MailSyncTests: XCTestCase {
    func testWaitingForPairs() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "waiting-pairs", withExtension: "tsv", subdirectory: "Fixtures/phase3/mail"))
        let rows = try BenchFixtures.rows(url).filter { $0.count >= 3 }
        XCTAssertEqual(rows.count, 30)
        var found = 0, wrong = 0
        var misses: [String] = []
        for r in rows {
            let hit = Engine.waitingMatch(sender: r[0], title: r[1])
            if r[2] == "1" { if hit { found += 1 } else { misses.append("missed: \(r[1])") } }
            else if hit { wrong += 1; misses.append("wrong: \(r[1])") }
        }
        print("waiting for: \(found) of 15 found, \(wrong) wrong")
        XCTAssertGreaterThanOrEqual(found, 13, misses.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(wrong, 2, misses.joined(separator: "\n"))
    }

    func engineWithMail(_ box: FixtureMail) -> (Engine, MemoryOutput, FixedClock) {
        let (e, out, clock) = makeEngine()
        e.settings.owner.addresses = ["maya.rao@example.com"]
        e.mailSource = box
        return (e, out, clock)
    }

    static func msg(_ id: String, at: Date, from: String = "Sam Lee", list: Bool = false, replied: Bool = false) -> MailMessage {
        MailMessage(id: id, messageID: "<\(id)@x.example>", fromName: from, fromAddress: "sam.lee@example.net",
                    to: ["maya.rao@example.com"], cc: [], subject: "Quote for the tiles", date: at, listHeader: list,
                    replied: replied, text: "Here is the quote.")
    }

    func testArrivalForWaitingFor() {
        let box = FixtureMail(messages: [Self.msg("m1", at: wed(9))])
        let (e, out, clock) = engineWithMail(box)
        e.handle(.command(id: "1", lead: "todo", text: "waiting for Sam's quote", context: [:]))
        _ = out.take()
        e.readMailIfDue()
        let flags = e.store?.openFlags() ?? []
        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags.first.map(e.flagLine), "Arrived? · Sam Lee · Quote for the tiles")
        XCTAssertEqual(e.store?.seen(.mail, "m1")?.result, .flag)
        // No new read before the interval. Then the cheap check only.
        let calls = box.calls
        e.readMailIfDue()
        XCTAssertEqual(box.calls, calls)
        clock.now = wed(10, 6)
        e.readMailIfDue()
        XCTAssertEqual(box.calls, calls + 2) // the newest id, and the open flag reply check
        // The owner replies in Mail: the flag is answered at the next read.
        box.setReplied("m1")
        clock.now = wed(10, 12)
        e.readMailIfDue()
        XCTAssertTrue(e.store?.openFlags().isEmpty ?? false)
    }

    func testMailNotRunningOrInFront() {
        let box = FixtureMail(messages: [Self.msg("m1", at: wed(9))])
        let (e, _, clock) = engineWithMail(box)
        box.isRunning = false
        e.readMailIfDue()
        XCTAssertEqual(box.calls, 0)
        box.isRunning = true
        box.isFront = true
        e.readMailIfDue()
        XCTAssertEqual(box.calls, 0)
        clock.now = wed(10, 29)
        e.readMailIfDue()
        XCTAssertEqual(box.calls, 0)
        // After 30 minutes in front: one small read.
        clock.now = wed(10, 31)
        e.readMailIfDue()
        XCTAssertGreaterThan(box.calls, 0)
    }

    func testNoFloodAtFirstRead() {
        // 500 old messages from senders that each match one "waiting for" item. The first read reads 3 days only,
        // and makes 5 flags or fewer.
        let names = ["Sam Lee", "Helen Ward", "Tom Hale", "Priya Shah", "Kofi Mensah", "Anna Novak", "Grace Kim", "Ravi Patel"]
        var msgs: [MailMessage] = []
        for i in 0..<500 {
            msgs.append(Self.msg("o\(i)", at: wed(9).addingTimeInterval(-Double(i) * 1800), from: names[i % names.count]))
        }
        let box = FixtureMail(messages: msgs)
        let (e, out, clock) = engineWithMail(box)
        for n in names { e.handle(.command(id: n, lead: "todo", text: "waiting for \(n.split(separator: " ")[0])", context: [:])) }
        _ = out.take()
        for k in 0..<40 {
            clock.now = wed(10).addingTimeInterval(Double(k) * 360)
            e.readMailIfDue()
        }
        XCTAssertLessThanOrEqual(e.store?.openFlags().count ?? 99, 5)
        XCTAssertEqual(e.store?.meta("mail.firstDone"), "1")
    }

    func testRequestFlagLine() {
        var m = Self.msg("r1", at: wed(9))
        m.subject = "Signed form"
        m.text = "Hi Maya,\n\nCould you send me the signed form before 20 November?\n\nThanks,\nSam"
        let box = FixtureMail(messages: [m, Self.msg("n1", at: wed(8), list: true)])
        let (e, _, _) = engineWithMail(box)
        // The default is "list" (the owner's choice after E11).
        XCTAssertEqual(e.settings.rules.request, .list)
        e.readMailIfDue()
        let flags = e.store?.openFlags(kind: .request) ?? []
        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags.first.map(e.flagLine), "Request · Sam Lee · Could you send me the signed form before 20 November? · 19 Nov?")
        // The time reader reads "before 20 November" as due on 19 November.
        // rules.request off: no request flag.
        let (e2, _, _) = engineWithMail(FixtureMail(messages: [m]))
        e2.settings.rules.request = .off
        e2.readMailIfDue()
        XCTAssertTrue(e2.store?.openFlags().isEmpty ?? false)
    }
}

/// 8.8: "3 drops and no keep" stops the flags from that sender; the flags page lists open flags. Made-up mail.
extension MailSyncTests {
    func requestMail(_ id: String, _ subject: String, at: Date) -> MailMessage {
        var m = Self.msg(id, at: at)
        m.subject = subject
        m.text = "Hi Maya,\n\nCould you send me the signed form for \(subject) by Friday?\n\nThanks,\nSam"
        return m
    }

    func testThreeDropsMuteTheSender() throws {
        let (e, _, _) = engineWithMail(FixtureMail(messages: []))
        for (i, s) in ["tiles", "roof", "garden"].enumerated() {
            let id = try XCTUnwrap(try e.requestFlag(requestMail("d\(i)", s, at: wed(9 + i))))
            _ = e.dropFlag(id: "c\(i)", try XCTUnwrap(e.store?.flag(id)))
        }
        XCTAssertEqual(e.settings.flagsMuted, ["sam.lee@example.net"])
        // The settings file has the line; the other settings stay.
        let (s, problem) = PASettings.load(e.settingsURL)
        XCTAssertNil(problem)
        XCTAssertEqual(s.flagsMuted, ["sam.lee@example.net"])
        XCTAssertNil(try e.requestFlag(requestMail("d9", "fence", at: wed(15))))
        e.flushPages(force: true)
        let today = try String(contentsOf: e.pagesFolder.appendingPathComponent("today.html"), encoding: .utf8)
        XCTAssertTrue(today.contains("No more flags from") && today.contains("Sam Lee"))
    }

    func testAKeepStopsTheMute() throws {
        let (e, _, _) = engineWithMail(FixtureMail(messages: []))
        let k = try XCTUnwrap(try e.requestFlag(requestMail("k0", "tiles", at: wed(8))))
        e.handle(.command(id: "w", lead: "what is new", text: "", context: [:]))
        _ = e.keepFlag(id: "k", text: "1", context: [:])
        XCTAssertEqual(e.store?.flag(k)?.state, .kept)
        for (i, s) in ["roof", "garden", "fence"].enumerated() {
            let id = try XCTUnwrap(try e.requestFlag(requestMail("d\(i)", s, at: wed(9 + i))))
            _ = e.dropFlag(id: "c\(i)", try XCTUnwrap(e.store?.flag(id)))
        }
        XCTAssertEqual(e.settings.flagsMuted, [])
    }

    func testFlagsPageListsOpenFlags() throws {
        let (e, _, _) = engineWithMail(FixtureMail(messages: []))
        _ = try e.requestFlag(requestMail("p0", "tiles", at: wed(9)))
        e.flushPages(force: true)
        let html = try String(contentsOf: e.pagesFolder.appendingPathComponent("flags.html"), encoding: .utf8)
        XCTAssertTrue(html.contains("Request · Sam Lee · Could you send me the signed form for tiles by Friday?"))
        XCTAssertTrue(html.contains("message://%3Cp0@x.example%3E"))
        XCTAssertTrue(html.contains("about half of the requests"))
        XCTAssertFalse(html.contains("<script"))
    }
}
