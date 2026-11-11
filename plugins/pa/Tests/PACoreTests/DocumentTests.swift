import Foundation
import XCTest
@testable import PACore

/// Phase 2, Q2: kept files and their text (build spec 7.2 to 7.5). All files and words are made-up.
final class DocumentTests: XCTestCase {
    func engine() -> (Engine, MemoryOutput, FixedClock) {
        let clock = FixedClock(wed(10))
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: clock, output: out, textReader: FileTextReader())
        e.start()
        e.settings.projectFocusMinutes = 0
        return (e, out, clock)
    }

    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "", _ ctx: [String: String] = [:]) -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
        return out.take().last!
    }

    func file(_ name: String, _ text: String) -> URL {
        let url = tempFolder().appendingPathComponent(name)
        try! Data(text.utf8).write(to: url)
        return url
    }

    static let quote = "Quote from Harbour Ceramics for the floor tiles. The porcelain tiles cost 42 pounds per square metre. Delivery takes ten working days."

    func testStoreIsVersion2WithNewColumns() throws {
        let (e, _, _) = engine()
        let db = e.store!.db
        XCTAssertEqual(try db.query("PRAGMA user_version").first?.first?.int, 2)
        let docCols = try db.query("PRAGMA table_info(doc)").compactMap { $0[1].text }
        for c in ["path", "kind", "size", "modified_at", "text_state", "passages", "parent_doc_id"] { XCTAssertTrue(docCols.contains(c), c) }
        let itemCols = try db.query("PRAGMA table_info(item)").compactMap { $0[1].text }
        XCTAssertTrue(itemCols.contains("project_by") && itemCols.contains("project_score"))
        // The migration can run again with no error.
        try db.exec("PRAGMA user_version = 1")
        try e.store!.migrate()
        XCTAssertEqual(try db.query("PRAGMA user_version").first?.first?.int, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: e.indexURL.path))
    }

    func testMigrationKeepsAPhase1Store() throws {
        let folder = tempFolder()
        let url = folder.appendingPathComponent("pa.sqlite")
        do {
            let s = try Store(url: url)
            let p = try s.insertProject("Kitchen", at: wed(9))
            var it = Item(kind: .todo, said: "order the paint for kitchen", title: "order the paint", createdAt: wed(9))
            it.projectID = p.id
            _ = try s.insert(it)
            // Make it look like phase 1: no project_by, version 1.
            try s.db.exec("UPDATE item SET project_by = NULL; PRAGMA user_version = 1")
            s.db.close()
        }
        let s = try Store(url: url)
        XCTAssertEqual(s.openItems().first?.title, "order the paint")
        XCTAssertEqual(s.openItems().first?.projectBy, "owner")
    }

    func testKeepThisFileReadsTheText() throws {
        let (e, out, _) = engine()
        say(e, out, "new project", "kitchen")
        let f = file("quote-tiles.txt", Self.quote)
        let a = say(e, out, "keep this", "for kitchen", ["app": "com.apple.TextEdit", "document": f.path, "windowTitle": "quote-tiles.txt"])
        XCTAssertEqual(a.text, "Kept · Kitchen · quote-tiles.txt")
        let d = e.store!.doc(path: f.path)!
        XCTAssertEqual(d.kind, .file)
        XCTAssertEqual(d.textState, .read)
        XCTAssertEqual(d.passages, 1)
        XCTAssertEqual(e.index!.search("porcelain", limit: 5).first?.docID, d.id)
        // The same file again: one reference.
        say(e, out, "keep this", "", ["document": f.path])
        XCTAssertEqual(e.store!.docs(project: nil).count, 1)
    }

    func testTextStates() throws {
        let (e, out, _) = engine()
        let md = file("plan.md", "# Plan\n\nPaint the shed in May. Buy the green paint first.")
        let html = file("page.html", "<html><head><title>x</title><script>var a = 1;</script></head><body><p>The shed door needs a new hinge.</p></body></html>")
        let other = file("photo.jpg", "not a picture")
        let empty = file("empty.txt", "   \n ")
        let big = tempFolder().appendingPathComponent("big.txt")
        try Data(count: Int(FileTextReader.maxBytes) + 10).write(to: big)
        for f in [md, html, other, empty, big] { say(e, out, "keep this", "", ["document": f.path]) }
        let s = e.store!
        XCTAssertEqual(s.doc(path: md.path)?.textState, .read)
        XCTAssertEqual(s.doc(path: html.path)?.textState, .read)
        XCTAssertEqual(e.index!.passages(doc: s.doc(path: html.path)!.id).first?.text, "The shed door needs a new hinge.")
        XCTAssertEqual(s.doc(path: other.path)?.textState, TextState.none)
        XCTAssertEqual(s.doc(path: empty.path)?.textState, .noText)
        XCTAssertEqual(s.doc(path: big.path)?.textState, .tooLarge)
    }

    func testChangedFileAndGoneFile() throws {
        let (e, out, clock) = engine()
        let f = file("notes.txt", "The plumber comes on Monday.")
        say(e, out, "keep this", "", ["document": f.path])
        let id = e.store!.doc(path: f.path)!.id
        try Data("The plumber comes on Tuesday. He brings the new valve.".utf8).write(to: f)
        clock.now = wed(12)
        e.checkFilesIfDue()
        XCTAssertEqual(e.index!.search("valve", limit: 5).first?.docID, id)
        XCTAssertTrue(e.index!.search("monday", limit: 5).isEmpty)
        try FileManager.default.removeItem(at: f)
        clock.now = wed(14)
        e.checkFilesIfDue()
        XCTAssertEqual(e.store!.doc(id)?.textState, .gone)
        // A gone file keeps its reference and its old passages.
        XCTAssertEqual(e.index!.search("valve", limit: 5).first?.docID, id)
        e.flushPages(force: true)
        let all = try String(contentsOf: e.pagesFolder.appendingPathComponent("all-open.html"), encoding: .utf8)
        XCTAssertFalse(all.contains("valve"))
    }

    func testDropDeletesTheTextAtOnce() throws {
        let (e, out, _) = engine()
        let f = file("letter.txt", "Dear owner, the gutter repair costs 300 pounds.")
        say(e, out, "keep this", "", ["document": f.path])
        say(e, out, "where is", "letter")
        XCTAssertEqual(say(e, out, "drop", "1").text, "Dropped · letter.txt")
        XCTAssertTrue(e.index!.search("gutter", limit: 5).isEmpty)
        XCTAssertEqual(e.index!.passageCount(), 0)
        // The file itself stays (R-PA-3).
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.path))
    }

    func testNoDocumentKeyIsPhase1() {
        let (e, out, _) = engine()
        let a = say(e, out, "keep this", "", ["app": "com.apple.Safari", "url": "https://example.com/tiles", "windowTitle": "Tiles"])
        XCTAssertEqual(a.text, "Kept · Tiles")
        XCTAssertEqual(e.store!.docs(project: nil).first?.kind, .page)
        XCTAssertEqual(say(e, out, "keep this").text, "Nothing kept. No page or document here.")
    }

    func testNoteThisSavesTheSelection() {
        let (e, out, _) = engine()
        say(e, out, "new project", "kitchen")
        let sel = "The fitter needs the room empty by Monday, and the floor must be level within three millimetres over two metres."
        let a = say(e, out, "note", "this for kitchen", ["selection": sel, "url": "https://example.com/fitter", "windowTitle": "Fitter"])
        XCTAssertEqual(a.text, "Note · Kitchen · " + String(sel.prefix(60)) + "…")
        let it = e.store!.openItems().last!
        XCTAssertEqual(it.said, sel)
        XCTAssertNotNil(it.docID)
        XCTAssertEqual(it.projectBy, "owner")
        // No selection: the words are a normal note.
        XCTAssertEqual(say(e, out, "note", "this").text, "Note · this")
        // A long selection: 2,000 characters are kept, and the PA still answers.
        let long = String(repeating: "made-up words ", count: 400)
        XCTAssertTrue(say(e, out, "note", "this", ["selection": long]).text.hasPrefix("Note · made-up"))
        XCTAssertEqual(e.store!.openItems().last!.said.count, 2000)
    }

    func testWhatProjectsAndFinishProject() {
        let (e, out, _) = engine()
        say(e, out, "new project", "kitchen")
        say(e, out, "new project", "garden")
        say(e, out, "todo", "order the paint for kitchen")
        say(e, out, "todo", "call the tiler for kitchen")
        let list = say(e, out, "what projects")
        XCTAssertEqual(list.text, "Projects")
        XCTAssertEqual(list.items, ["Garden · 0 open", "Kitchen · 2 open"])
        XCTAssertEqual(say(e, out, "finish project", "kitchen").text, "Project closed · Kitchen · 2 items still open")
        XCTAssertFalse(e.targets().contains { $0.name == "Kitchen" })
        XCTAssertEqual(say(e, out, "what projects").items, ["Garden · 0 open"])
        // A closed project is not a target for "for kitchen".
        say(e, out, "todo", "buy the handles for kitchen")
        XCTAssertNil(e.store!.openItems().last!.projectID)
        e.flushPages(force: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: e.pagesFolder.appendingPathComponent("project-kitchen.html").path))
        XCTAssertEqual(say(e, out, "new project", "kitchen").text, "Project · Kitchen · open again")
        XCTAssertTrue(e.targets().contains { $0.name == "Kitchen" })
        XCTAssertEqual(say(e, out, "finish project", "attic").text, "No project attic.")
    }

    func testHTMLText() {
        let t = FileTextReader.htmlText("<div>One &amp; two</div><style>.a{}</style><ul><li>Three</li></ul><!-- c -->")
        XCTAssertEqual(t, "One & two\nThree")
    }
}
