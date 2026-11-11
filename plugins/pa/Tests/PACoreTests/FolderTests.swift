import Foundation
import XCTest
@testable import PACore

/// Phase 2, Q6: "keep this folder" and new files (build spec 8.5). All files and words are made-up.
final class FolderTests: XCTestCase {
    final class FakeWatcher: FolderWatcher {
        var folders: [String] = []
        func watch(_ folders: [String], _ handler: @escaping ([String]) -> Void) { self.folders = folders }
    }

    func engine() -> (Engine, MemoryOutput, FakeWatcher) {
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        let w = FakeWatcher()
        e.folderWatcher = w
        e.start()
        e.settings.projectFocusMinutes = 0
        return (e, out, w)
    }

    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "", _ ctx: [String: String] = [:]) -> String {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
        return out.take().compactMap { m -> String? in
            if case .answer(let re, _, let t, _) = m, re != nil { return t } else { return nil }
        }.last ?? ""
    }

    func write(_ url: URL, _ text: String) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(text.utf8).write(to: url)
    }

    func folder() -> URL {
        let root = tempFolder().appendingPathComponent("kitchen-papers", isDirectory: true)
        write(root.appendingPathComponent("quote-tiles.txt"), "Quote from Harbour Ceramics for the floor tiles.")
        write(root.appendingPathComponent("plan.md"), "Paint the walls in May.")
        write(root.appendingPathComponent("photo.jpg"), "not text")
        write(root.appendingPathComponent(".hidden.txt"), "hidden words")
        write(root.appendingPathComponent("a/b/deep.txt"), "Level three file about the sink.")
        write(root.appendingPathComponent("a/b/c/too-deep.txt"), "Level four file about the tap.")
        write(root.appendingPathComponent("code/.git/HEAD"), "ref")
        write(root.appendingPathComponent("code/readme.md"), "A repository readme.")
        return root
    }

    func testKeepThisFolderReadsTheFiles() throws {
        let (e, out, w) = engine()
        say(e, out, "new project", "kitchen")
        let root = folder()
        XCTAssertEqual(say(e, out, "keep this", "folder for kitchen", ["document": root.path]),
                       "Kept · Kitchen · kitchen-papers · 3 files")
        let files = e.store!.docs(where: "parent_doc_id IS NOT NULL").map(\.title).sorted()
        XCTAssertEqual(files, ["deep.txt", "plan.md", "quote-tiles.txt"])
        XCTAssertTrue(e.store!.docs(where: "parent_doc_id IS NOT NULL").allSatisfy { $0.textState == .read })
        XCTAssertEqual(w.folders, [root.path])
        XCTAssertEqual(e.index!.search("ceramics", limit: 5).count, 1)
        // The project page shows the folder with its count, not each file.
        e.flushPages(force: true)
        let page = try String(contentsOf: e.pagesFolder.appendingPathComponent("project-kitchen.html"), encoding: .utf8)
        XCTAssertTrue(page.contains("kitchen-papers</a> · folder, 3 files"))
        XCTAssertFalse(page.contains(">plan.md<"))
    }

    func testNoFolderInFront() {
        let (e, out, _) = engine()
        XCTAssertEqual(say(e, out, "keep this", "folder"), "No folder here. Nothing kept.")
        let f = tempFolder().appendingPathComponent("one.txt")
        write(f, "words")
        XCTAssertEqual(say(e, out, "keep this", "folder", ["document": f.path]), "No folder here. Nothing kept.")
    }

    func testMoreThanTheLimit() {
        let (e, out, _) = engine()
        let root = tempFolder().appendingPathComponent("many", isDirectory: true)
        for i in 0..<510 { write(root.appendingPathComponent("note-\(i).txt"), "Made-up note number \(i).") }
        XCTAssertEqual(say(e, out, "keep this", "folder", ["document": root.path]), "Kept · 500 of 510 files")
        XCTAssertEqual(e.store!.docs(where: "parent_doc_id IS NOT NULL").count, 500)
    }

    func testANewFileIsReadAndIsANewArrival() throws {
        let (e, out, _) = engine()
        say(e, out, "new project", "kitchen")
        let root = folder()
        say(e, out, "keep this", "folder for kitchen", ["document": root.path])
        let new = root.appendingPathComponent("quote-2.txt")
        write(new, "Second quote from Harbour Ceramics for the wall tiles.")
        e.foldersChanged([new.path, root.appendingPathComponent("photo2.jpg").path])
        let d = try XCTUnwrap(e.store!.doc(path: new.path))
        XCTAssertEqual(d.textState, .read)
        XCTAssertEqual(e.arrivals(since: wed(0)).map(\.title), ["quote-2.txt"])
        XCTAssertEqual(e.arrivalText(d), "New in Kitchen · quote-2.txt")
        // Default "list": no alert now, a line on the project page.
        XCTAssertFalse(out.take().contains { if case .answer(nil, .alert, _, _) = $0 { return true } else { return false } })
        e.flushPages(force: true)
        let page = try String(contentsOf: e.pagesFolder.appendingPathComponent("project-kitchen.html"), encoding: .utf8)
        XCTAssertTrue(page.contains("New in Kitchen · quote-2.txt"))
        // The same path again: no second arrival.
        e.foldersChanged([new.path])
        XCTAssertEqual(e.arrivals(since: wed(0)).count, 1)
    }

    func testNewArrivalAlertAndDeletedFile() throws {
        let (e, out, _) = engine()
        e.settings.rules.newArrival = .alert
        let root = folder()
        say(e, out, "keep this", "folder", ["document": root.path])
        let new = root.appendingPathComponent("letter.txt")
        write(new, "A made-up letter from the council.")
        e.foldersChanged([new.path])
        XCTAssertTrue(out.take().contains { if case .answer(nil, .alert, "New · letter.txt", _) = $0 { return true } else { return false } })
        try FileManager.default.removeItem(at: new)
        e.foldersChanged([new.path])
        XCTAssertEqual(e.store!.doc(path: new.path)?.textState, .gone)
    }

    func testDropFolderDropsItsFilesAndText() {
        let (e, out, w) = engine()
        let root = folder()
        say(e, out, "keep this", "folder", ["document": root.path])
        say(e, out, "drop", "that")
        XCTAssertEqual(e.store!.docs(where: "dropped_at IS NULL").count, 0)
        XCTAssertEqual(e.index!.passageCount(), 0)
        XCTAssertEqual(w.folders, [])
    }
}
