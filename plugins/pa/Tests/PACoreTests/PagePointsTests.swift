import Foundation
@testable import PACore
import XCTest

/// Phase 4, W5: main points of a web page (spec section 10). Made-up pages only.
final class PagePointsTests: XCTestCase {
    func engine() -> (Engine, MemoryOutput, FixedClock) {
        let (e, out, clock) = makeEngine()
        e.models = ModelHost(modelID: "hash-256-v1") { HashEmbedder() }
        return (e, out, clock)
    }

    func lists(_ msgs: [Outgoing]) -> [(String, [String])] {
        msgs.compactMap { if case .answer(_, .list, let t, let items) = $0 { return (t, items) }; return nil }
    }

    func notes(_ msgs: [Outgoing]) -> [String] {
        msgs.compactMap { if case .answer(_, .note, let t, _) = $0 { return t }; return nil }
    }

    var pageText: String { PageKeepTests.story.map(\.text).joined(separator: "\n") }

    func testMainPointsOfThisPageAndNoTextKept() throws {
        let (e, out, _) = engine()
        e.handle(.command(id: "m1", lead: "main points", text: "of this", context: PageKeepTests.ctx))
        let first = out.take()
        XCTAssertEqual(notes(first), ["Main points · reading this page"])
        XCTAssertTrue(first.contains(.askPageText(re: "m1")))
        e.handle(.pageText(.part(re: "m1", part: 1, of: 1, complete: true, url: PageKeepTests.url,
                                 title: PageKeepTests.title, blocks: PageKeepTests.story)))
        let l = try XCTUnwrap(lists(out.take()).first)
        XCTAssertEqual(l.0, "Main points · Night ferry stays")
        XCTAssertFalse(l.1.isEmpty)
        XCTAssertLessThanOrEqual(l.1.count, 5)
        // Each full sentence of the page is a part of the page text, character for character.
        let html = try String(contentsOf: e.mainPointsPageURL, encoding: .utf8)
        for s in TextCut.sentences(pageText) where html.contains(Engine.escape(s)) { XCTAssertTrue(pageText.contains(s)) }
        for item in l.1 { XCTAssertTrue(pageText.contains(item.hasSuffix("…") ? String(item.dropLast()) : item), item) }
        XCTAssertFalse(l.1.contains { $0.contains("late shift") })
        // The page is not kept and its text is not kept.
        XCTAssertTrue(e.store!.docs(project: nil).isEmpty)
        XCTAssertEqual(e.index!.passageCount(), 0)
    }

    func testOffAnswersFilesOnly() {
        let (e, out, _) = engine()
        e.settings.pagePoints = false
        e.handle(.command(id: "m1", lead: "main points", text: "of this", context: PageKeepTests.ctx))
        let msgs = out.take()
        XCTAssertEqual(notes(msgs), ["Main points work for kept files only."])
        XCTAssertFalse(msgs.contains(.askPageText(re: "m1")))
    }

    func testNoTextOfThePage() {
        let (e, out, _) = engine()
        e.handle(.command(id: "m1", lead: "main points", text: "of this", context: PageKeepTests.ctx))
        out.take()
        e.handle(.pageText(.error(re: "m1", reason: "the page changed")))
        XCTAssertEqual(notes(out.take()), ["No text of this page. Nothing to show."])
    }

    func testMainPointsOfAKeptPage() throws {
        let (e, out, _) = engine()
        e.handle(.command(id: "k1", lead: "keep this", text: "", context: PageKeepTests.ctx))
        e.handle(.pageText(.part(re: "k1", part: 1, of: 1, complete: true, url: PageKeepTests.url,
                                 title: PageKeepTests.title, blocks: PageKeepTests.story)))
        out.take()
        e.handle(.command(id: "m2", lead: "main points", text: "of night ferry", context: [:]))
        let l = try XCTUnwrap(lists(out.take()).first)
        XCTAssertEqual(l.0, "Main points · Night ferry stays")
        for item in l.1 { XCTAssertTrue(pageText.contains(item.hasSuffix("…") ? String(item.dropLast()) : item), item) }
        // "drop" removes the main text file too.
        let d = e.store!.docs(where: "kind = 'page'").first!
        XCTAssertNotNil(e.keptPageText(d))
        e.handle(.command(id: "w", lead: "where is", text: "night ferry", context: [:]))
        out.take()
        e.handle(.command(id: "d", lead: "drop", text: "1", context: [:]))
        XCTAssertEqual(notes(out.take()).first, "Dropped · Night ferry stays")
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.keptTextURL(d.id).path))
    }

    func testSamePoint() {
        XCTAssertTrue(PageBench.samePoint("The vote was  seven to two.", "the vote was seven to two"))
        XCTAssertFalse(PageBench.samePoint("The vote was seven.", "The vote was seven to two."))
    }
}
