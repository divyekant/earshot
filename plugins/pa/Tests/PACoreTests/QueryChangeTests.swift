import Foundation
import XCTest
@testable import PACore

/// Lists, search and changes (build spec 9.5 and 9.6). Made-up items only.
final class QueryChangeTests: XCTestCase {
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        return out.take().last!
    }

    func testWhatIsDueOrderAndNumbers() {
        let (e, out, clock) = makeEngine()
        XCTAssertEqual(say(e, out, "what is due").text, "Nothing is due.")
        say(e, out, "todo", "send the tax papers by tomorrow")
        say(e, out, "remind me", "to call the plumber at 5")
        say(e, out, "remind me", "to water the plants at 11")
        say(e, out, "todo", "renew the passport on the 20th")
        clock.now = wed(10).addingTimeInterval(-86400)  // a late item: made yesterday, due yesterday
        say(e, out, "todo", "pay the gardener today")
        clock.now = wed(10)
        let list = say(e, out, "what due")
        XCTAssertEqual(list.kind, .list)
        XCTAssertEqual(list.text, "Due")
        XCTAssertEqual(list.items, ["pay the gardener · Tue 10 Nov", "water the plants · 11:00", "call the plumber · 17:00",
                                    "send the tax papers · tomorrow"])
        XCTAssertEqual(say(e, out, "done", "2").text, "Done · water the plants")
        XCTAssertEqual(say(e, out, "done", "number 9").text, "No item 9 in the last list.")
        XCTAssertEqual(say(e, out, "what is due").items.count, 3)
    }

    func testMoreThanTenLines() {
        let (e, out, _) = makeEngine()
        for n in 1...12 { say(e, out, "todo", "made-up task \(n) by tomorrow") }
        let list = say(e, out, "what is due")
        XCTAssertEqual(list.items.count, 10)
        XCTAssertEqual(list.items.last, "and 3 more")
    }

    func testWhatAboutAndWhereIs() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "what about", "kitchen").text, "No project kitchen.")
        say(e, out, "new project", "kitchen")
        say(e, out, "todo", "call the tile shop for kitchen")
        say(e, out, "todo", "order the paint for kitchen by Friday")
        e.handle(.command(id: "k", lead: "keep this", text: "for kitchen", context: ["windowTitle": "quote-tiles.pdf"]))
        _ = out.take()
        let p = say(e, out, "what about", "the kitchen please")
        XCTAssertEqual(p.text, "Kitchen")
        XCTAssertEqual(p.items, ["order the paint · Fri 13 Nov", "call the tile shop", "1 document"])
        let found = say(e, out, "where is", "the tile quote")
        XCTAssertEqual(found.items.first, "quote-tiles.pdf · document · Kitchen")
        XCTAssertEqual(say(e, out, "where is", "the boat").text, "Nothing found for the boat.")
        let tiles = say(e, out, "where is", "my tile")
        XCTAssertEqual(tiles.text, "Found")
        XCTAssertTrue(tiles.items.contains("call the tile shop · to-do · Kitchen"))
        XCTAssertTrue(tiles.items.contains("quote-tiles.pdf · document · Kitchen"))
    }

    func testChangesByWordsThatAndNumber() {
        let (e, out, _) = makeEngine()
        say(e, out, "new project", "garden")
        say(e, out, "todo", "fix the gate")
        say(e, out, "todo", "fix the shed door")
        XCTAssertEqual(say(e, out, "move", "it to garden").text, "Moved · Garden · fix the shed door")
        XCTAssertEqual(say(e, out, "move", "it to the moon").text, "No project moon.")
        XCTAssertEqual(say(e, out, "move", "it to no project").text, "Moved · no project · fix the shed door")
        let which = say(e, out, "done", "fix")
        XCTAssertEqual(which.text, "Which one? Say the command with a number.")
        XCTAssertEqual(which.items.count, 2)
        XCTAssertEqual(say(e, out, "done", "1").text, "Done · fix the gate")
        XCTAssertEqual(say(e, out, "done", "the gate").text, "No open item for the gate.")
        XCTAssertEqual(say(e, out, "drop", "that").text, "Dropped · fix the shed door")
        XCTAssertEqual(e.store!.openItems().count, 0)
    }

    func testSnooze() {
        let (e, out, _) = makeEngine()
        say(e, out, "remind me", "to call the plumber at 5")
        say(e, out, "what is due")
        XCTAssertEqual(say(e, out, "snooze", "1 to tomorrow morning").text, "Snoozed · tomorrow 09:00 · call the plumber")
        XCTAssertEqual(say(e, out, "snooze", "1 for 20 minutes").text, "Snoozed · today 10:20 · call the plumber")
        XCTAssertEqual(say(e, out, "snooze", "").text, "Snoozed · today 10:10 · call the plumber")
        XCTAssertEqual(say(e, out, "snooze", "the plumber until 6").text, "Snoozed · today 18:00 · call the plumber")
        XCTAssertEqual(say(e, out, "snooze", "1 to kal subah").text, "No time. Nothing changed.")
    }
}
