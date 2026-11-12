import Foundation
import XCTest
@testable import PACore

/// Phase 3, package S6: notes as documents for "where is" (spec 10). Made-up notes only.
final class NotesTests: XCTestCase {
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        return out.take().last!
    }

    func notes() -> FixtureNotes {
        FixtureNotes([
            (NoteHeader(id: "n1", name: "Kitchen plan", modifiedAt: wed(8)),
             "Kitchen plan\nCall the plumber about the leak under the sink.\nThe grout colour is light grey."),
            (NoteHeader(id: "n2", name: "Gift ideas", modifiedAt: wed(7)), "Gift ideas\nA blue scarf for Priya."),
            (NoteHeader(id: "n3", name: "Old list", modifiedAt: wed(6), folder: "Recently Deleted"), "Old list\nThe purple umbrella."),
            (NoteHeader(id: "n4", name: "Secret", modifiedAt: wed(6), locked: true), "Secret\nThe orange lantern."),
        ])
    }

    func testNotesAreFoundAndFollowChanges() throws {
        let (e, out, clock) = makeEngine()
        let src = notes()
        e.notesSource = src
        e.readNotesIfDue()
        let store = try XCTUnwrap(e.store)
        XCTAssertEqual(store.docs(where: "kind = 'note' AND dropped_at IS NULL").count, 2)
        var r = say(e, out, "where is", "grout colour")
        XCTAssertTrue(r.items.first?.hasPrefix("Kitchen plan") ?? false, r.items.joined(separator: "\n"))
        // Locked notes and "Recently Deleted" are not read.
        XCTAssertFalse(say(e, out, "where is", "purple umbrella").items.contains { $0.contains("umbrella") })
        XCTAssertFalse(say(e, out, "where is", "orange lantern").items.contains { $0.contains("lantern") })
        // A change: the passages are new.
        src.items[0] = (NoteHeader(id: "n1", name: "Kitchen plan", modifiedAt: wed(10, 30)), "Kitchen plan\nThe tiles are dark green.")
        clock.now = wed(10, 20)
        e.readNotesIfDue()
        r = say(e, out, "where is", "dark green tiles")
        XCTAssertTrue(r.items.first?.hasPrefix("Kitchen plan") ?? false)
        XCTAssertFalse(say(e, out, "where is", "grout colour").items.contains { $0.contains("grout") })
        // A gone note: its passages go at once.
        src.items.remove(at: 1)
        clock.now = wed(10, 40)
        e.readNotesIfDue()
        XCTAssertFalse(say(e, out, "where is", "blue scarf").items.contains { $0.contains("scarf") })
        // Notes off: all note documents go.
        var s = e.settings
        let old = s
        s.sources.notes = false
        e.settings = s
        e.settingsChanged(from: old)
        XCTAssertEqual(store.docs(where: "kind = 'note'").count, 0)
        XCTAssertEqual(e.index?.passageCount(), 0)
    }

    func testNotesNotRunning() {
        let (e, _, _) = makeEngine()
        let src = notes()
        src.isRunning = false
        e.notesSource = src
        e.readNotesIfDue()
        XCTAssertEqual(e.store?.docs(where: "kind = 'note'").count, 0)
    }
}
