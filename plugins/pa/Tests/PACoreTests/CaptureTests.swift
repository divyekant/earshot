import Foundation
import XCTest
@testable import PACore

/// The capture rules (build spec 9.1 to 9.4). Made-up items only.
final class CaptureTests: XCTestCase {
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String, _ ctx: [String: String] = [:]) -> String {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
        return out.take().last?.text ?? ""
    }

    func testReminderNotes() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "remind me", "to call the plumber at 5"), "Reminder · today 17:00 · call the plumber")
        XCTAssertEqual(say(e, out, "remind me", "to call the plumber"), "Reminder · no time · call the plumber")
        XCTAssertEqual(say(e, out, "remind me", "to open Slack at 9"), "Reminder · today 21:00 · open Slack")
        XCTAssertEqual(say(e, out, "remind me", "to water the plants tomorrow"), "Reminder · tomorrow 09:00 · water the plants")
        let items = e.store!.openItems()
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].said, "to call the plumber at 5")
        XCTAssertTrue(items[0].hasClock)
        XCTAssertFalse(items[3].hasClock)
    }

    func testTodoNotesAndProject() throws {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "todo", "send the tax papers by Friday"), "To-do · due Fri 13 Nov · send the tax papers")
        XCTAssertEqual(say(e, out, "new project", "kitchen"), "Project · Kitchen")
        XCTAssertEqual(say(e, out, "new project", "Kitchen"), "Project Kitchen is there already.")
        XCTAssertEqual(say(e, out, "todo", "call the tile shop for kitchen"), "To-do · Kitchen · call the tile shop")
        XCTAssertEqual(say(e, out, "task", "order the paint for the kitchen by Monday"), "To-do · due Mon 16 Nov · Kitchen · order the paint")
        XCTAssertEqual(say(e, out, "remind me", "to buy flowers for mom"), "Reminder · no time · buy flowers for mom")
    }

    func testNoteKeepsWordsAndReadsNoTime() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "note", "the landlord wants two months notice by Friday."),
                       "Note · the landlord wants two months notice by Friday")
        XCTAssertEqual(say(e, out, "note", "please don't paint the shed"), "Note · don't paint the shed")
    }

    func testEmptyLongAndDuplicate() {
        let (e, out, clock) = makeEngine()
        XCTAssertEqual(say(e, out, "todo", "  "), "No words. Nothing saved.")
        let long = String(repeating: "word ", count: 1000)
        _ = say(e, out, "note", long)
        let saved = e.store!.openItems().last!
        XCTAssertEqual(saved.said.count, long.trimmingCharacters(in: .whitespaces).count)
        XCTAssertEqual(saved.title.count, 200)
        let a = say(e, out, "todo", "fix the gate")
        let b = say(e, out, "todo", "fix the gate")
        XCTAssertEqual(a, b)
        XCTAssertEqual(e.store!.openItems().count, 2)
        clock.advance(minutes: 2)
        _ = say(e, out, "todo", "fix the gate")
        XCTAssertEqual(e.store!.openItems().count, 3)
    }

    func testKeepThis() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "keep this", ""), "Nothing kept. No page or document here.")
        _ = say(e, out, "new project", "kitchen")
        XCTAssertEqual(say(e, out, "keep this", "for kitchen", ["app": "com.apple.Preview", "windowTitle": "quote-tiles.pdf"]),
                       "Kept · Kitchen · quote-tiles.pdf")
        XCTAssertEqual(e.store!.docs(project: nil).count, 1)
        XCTAssertEqual(say(e, out, "remind me", "about this", ["url": "https://example.com/offer", "windowTitle": "Tile offer"]),
                       "Reminder · no time · Tile offer")
    }

    func testUnsureTimeSaysNoTime() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "todo", "call the bank kal subah at 5ish pm"), "To-do · no time · call the bank kal subah at 5ish pm")
    }
}
