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
