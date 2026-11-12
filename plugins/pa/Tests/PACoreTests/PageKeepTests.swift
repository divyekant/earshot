import Foundation
@testable import PACore
import XCTest

/// Phase 4, W4: the keep flow of a web page (spec 9.2 and 9.3). Made-up pages only. The blocks here test the flow;
/// the numbers of E12 come from blocks of the real read.
final class PageKeepTests: XCTestCase {
    static let story = [
        PageBlock("Menu", zone: "nav", links: 1),
        PageBlock("The night ferry to Varrow", kind: .h, level: 1, zone: "main", inMain: true),
        PageBlock("The council of Varrow voted on Tuesday to keep the night ferry for two more years. The vote was seven to two.",
                  zone: "main", inMain: true, links: 0),
        PageBlock("The ferry leaves the north pier at 23:40 and takes fifty minutes. A single ticket costs 6 pounds.",
                  zone: "main", inMain: true, links: 0),
        PageBlock("Timetable", kind: .h, level: 2, zone: "main", inMain: true),
        PageBlock("From 1 March the last ferry leaves ten minutes later, because the harbour works close the east berth.",
                  zone: "main", inMain: true, links: 0),
        PageBlock("Riders asked for a covered wait area. The council will look at the cost in the spring budget.",
                  zone: "main", inMain: true, links: 0),
        PageBlock("Comments (2)", kind: .h, level: 2, zone: "main", inMain: true),
        PageBlock("Great news for the late shift workers on the island.", zone: "main", inMain: true, links: 0),
        PageBlock("About us · Contact · Jobs", zone: "footer", links: 1),
    ]
    static let url = "https://varrow-news.example/ferry"
    static let title = "Night ferry stays"
    static var ctx: [String: String] { ["app": "com.apple.Safari", "url": url, "windowTitle": title] }

    func engine(_ pageText: Bool = true) -> (Engine, MemoryOutput, FixedClock) {
        let (e, out, clock) = makeEngine()
        e.settings.pageText = pageText
        return (e, out, clock)
    }

    /// Sends "keep this" and gives the command id and all messages that the PA sent.
    @discardableResult
    func keep(_ e: Engine, _ out: MemoryOutput, _ ctx: [String: String] = PageKeepTests.ctx) -> (id: String, msgs: [Outgoing]) {
        let id = UUID().uuidString
        e.handle(.command(id: id, lead: "keep this", text: "", context: ctx))
        return (id, out.take())
    }

    func send(_ e: Engine, _ re: String, _ blocks: [PageBlock], complete: Bool = true, part: Int = 1, of: Int = 1,
              url: String? = PageKeepTests.url) {
        e.handle(.pageText(.part(re: re, part: part, of: of, complete: complete, url: url, title: PageKeepTests.title, blocks: blocks)))
    }

    func notes(_ msgs: [Outgoing]) -> [String] {
        msgs.compactMap { if case .answer(_, _, let t, _) = $0 { return t }; return nil }
    }

    func asks(_ msgs: [Outgoing]) -> [String] {
        msgs.compactMap { if case .askPageText(let re) = $0 { return re }; return nil }
    }

    func page(_ e: Engine) -> Doc { e.store!.docs(where: "kind = 'page'").first! }

    func testKeepAnswersFirstThenAsksThenKeepsTheText() throws {
        let (e, out, _) = engine()
        let (id, msgs) = keep(e, out)
        XCTAssertEqual(notes(msgs), ["Kept · Night ferry stays"])
        // The answer comes first, then the ask with the id of the command.
        guard case .answer = msgs.first, case .askPageText(let re) = msgs[1] else { return XCTFail("\(msgs)") }
        XCTAssertEqual(re, id)

        send(e, id, Self.story)
        let after = notes(out.take())
        let d = page(e)
        XCTAssertEqual(d.textState, .read)
        XCTAssertGreaterThan(d.passages, 0)
        XCTAssertEqual(d.textAt, e.clock.now)
        XCTAssertEqual(after, ["Text kept · Night ferry stays · \(d.textWords!) words"])
        // The main text only: no menu, no footer, no comments.
        let copy = try String(contentsOf: e.keptCopyURL(d.id), encoding: .utf8)
        XCTAssertTrue(copy.contains("seven to two"))
        XCTAssertTrue(copy.contains("Text copy by the PA. The page on the web can be different now."))
        XCTAssertFalse(copy.contains("Menu"))
        XCTAssertFalse(copy.contains("late shift"))
        XCTAssertFalse(copy.contains("Jobs"))
        XCTAssertTrue(copy.contains("Content-Security-Policy"))
        XCTAssertFalse(e.index!.search("seven", limit: 5).isEmpty)
        XCTAssertTrue(e.index!.search("shift", limit: 5).isEmpty)

        // kept.html and the target "kept pages".
        e.flushPages(force: true)
        let list = try String(contentsOf: e.pagesFolder.appendingPathComponent("kept.html"), encoding: .utf8)
        XCTAssertTrue(list.contains("Night ferry stays"))
        XCTAssertTrue(list.contains("varrow-news.example"))
        XCTAssertTrue(list.contains("href=\"kept/\(d.id).html\""))
        XCTAssertTrue(e.targets().contains { $0.name == "kept pages" })

        // "where is": `Page · <title> · <site name> · <passage>`, and the copy link in search.html.
        e.handle(.command(id: "w1", lead: "where is", text: "the vote on the night ferry", context: [:]))
        let found = out.take().compactMap { m -> String? in
            if case .answer(_, _, let t, let items) = m { return ([t] + items).joined(separator: "\n") }; return nil
        }.joined(separator: "\n")
        XCTAssertTrue(found.contains("Page · Night ferry stays · varrow-news.example · "), found)
        let search = try String(contentsOf: e.searchPageURL, encoding: .utf8)
        XCTAssertTrue(search.contains("Text copy"))
    }

    func testTwoPartsInAnyOrder() {
        let (e, out, _) = engine()
        let (id, _) = keep(e, out)
        send(e, id, Array(Self.story[5...]), part: 2, of: 2, url: nil)
        XCTAssertTrue(notes(out.take()).isEmpty)
        send(e, id, Array(Self.story[..<5]), part: 1, of: 2)
        XCTAssertEqual(notes(out.take()).first?.hasPrefix("Text kept · Night ferry stays · "), true)
        XCTAssertEqual(page(e).textState, .read)
    }

    func testIncompleteReadIsPartial() {
        let (e, out, _) = engine()
        let (id, _) = keep(e, out)
        send(e, id, Self.story, complete: false)
        XCTAssertEqual(page(e).textState, .partial)
        XCTAssertEqual(notes(out.take()).first?.hasPrefix("Text kept in part · Night ferry stays · "), true)
    }

    func testNoTextNotes() {
        let reasons: [(String?, String)] = [
            ("the page changed", "Link kept. The PA has no text of this page. Say \"keep this\" again."),
            ("sign-in, code or payment page", "Link kept. The page has a password field, so earshot did not read it."),
            ("not a web page", "Link kept. The PA has no text of this page."),
        ]
        for (reason, note) in reasons {
            let (e, out, _) = engine()
            let (id, _) = keep(e, out)
            e.handle(.pageText(.error(re: id, reason: reason!)))
            XCTAssertEqual(notes(out.take()), [note])
            XCTAssertEqual(page(e).textState, .noText)
        }
        // A page with fewer than 50 words of main text.
        let (e, out, _) = engine()
        let (id, _) = keep(e, out)
        send(e, id, [PageBlock("A short page with few words in it.", zone: "main", inMain: true, links: 0)])
        XCTAssertEqual(notes(out.take()), ["Link kept. The PA has no text of this page."])
        XCTAssertEqual(page(e).textState, .noText)
        XCTAssertEqual(e.index!.passageCount(), 0)
    }

    /// The old earshot drops the ask: after 10 s the PA shows one note. The reference stays. No error.
    func testOldEarshotNoAnswerIn10Seconds() {
        let (e, out, clock) = engine()
        let (id, msgs) = keep(e, out)
        XCTAssertEqual(notes(msgs), ["Kept · Night ferry stays"])
        clock.now = clock.now.addingTimeInterval(9)
        e.tick()
        XCTAssertFalse(notes(out.take()).contains { $0.hasPrefix("Link kept") })
        clock.now = clock.now.addingTimeInterval(1)
        e.tick()
        XCTAssertEqual(notes(out.take()).filter { $0.hasPrefix("Link kept") }, ["Link kept. The PA has no text of this page."])
        // A late answer does nothing.
        send(e, id, Self.story)
        XCTAssertTrue(notes(out.take()).isEmpty)
        XCTAssertEqual(e.store!.docs(where: "kind = 'page'").count, 1)
    }

    func testSettingOffAsksNothing() {
        let (e, out, _) = engine(false)
        let (_, msgs) = keep(e, out)
        XCTAssertEqual(notes(msgs), ["Kept · Night ferry stays"])
        XCTAssertTrue(asks(msgs).isEmpty)
    }

    func testNoAskWithoutAWebAddress() {
        let (e, out, _) = engine()
        let (_, msgs) = keep(e, out, ["app": "com.apple.Notes", "windowTitle": "Shopping"])
        XCTAssertEqual(notes(msgs), ["Kept · Shopping"])
        XCTAssertTrue(asks(msgs).isEmpty)
    }

    /// The same page three times with other `utm_` values: one reference, the text of the last read.
    func testSamePageAgain() throws {
        let (e, out, clock) = engine()
        let urls = [Self.url + "?utm_source=a#top", Self.url + "?utm_source=b&fbclid=x", Self.url + "?gclid=y&utm_medium=c"]
        var last = ""
        for (i, u) in urls.enumerated() {
            clock.now = clock.now.addingTimeInterval(120)
            let (id, msgs) = keep(e, out, ["url": u, "windowTitle": Self.title])
            XCTAssertEqual(notes(msgs), [i == 0 ? "Kept · Night ferry stays" : "Kept again · Night ferry stays"])
            last = "The harbour master said read number \(i + 1) of the page is here."
            var blocks = Self.story
            blocks.insert(PageBlock(last, zone: "main", inMain: true, links: 0), at: 3)
            send(e, id, blocks)
            XCTAssertEqual(notes(out.take()).first,
                           i == 0 ? "Text kept · Night ferry stays · \(page(e).textWords!) words" : "Kept again · Night ferry stays · text updated")
        }
        XCTAssertEqual(e.store!.docs(where: "kind = 'page'").count, 1)
        let copy = try String(contentsOf: e.keptCopyURL(page(e).id), encoding: .utf8)
        XCTAssertTrue(copy.contains("read number 3"))
        XCTAssertFalse(copy.contains("read number 1"))
        // A query string that is not a tracking value makes another page.
        keep(e, out, ["url": Self.url + "?id=2", "windowTitle": "Other"])
        XCTAssertEqual(e.store!.docs(where: "kind = 'page'").count, 2)
    }

    func testDropDeletesPassagesNumbersAndCopy() {
        let (e, out, _) = engine()
        let (id, _) = keep(e, out)
        send(e, id, Self.story)
        let d = page(e)
        XCTAssertTrue(FileManager.default.fileExists(atPath: e.keptCopyURL(d.id).path))
        e.handle(.command(id: "w", lead: "where is", text: "night ferry", context: [:]))
        out.take()
        e.handle(.command(id: "d", lead: "drop", text: "1", context: [:]))
        XCTAssertEqual(notes(out.take()).first, "Dropped · Night ferry stays")
        XCTAssertEqual(e.index!.passageCount(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.keptCopyURL(d.id).path))
    }

    /// Spec 9.3: script, an image with onerror, a title with quotes and angle brackets and a javascript: link text
    /// show as plain text in the copy, kept.html and search.html.
    func testEscape() throws {
        let (e, out, _) = engine()
        let title = "Say \"hi\" <b>now</b> & 'then'"
        let bad = [
            "<script>alert('x')</script> is the text of a script element in this made-up page about the night ferry.",
            "<img src=x onerror=alert(1)> is an image element with an onerror value as text, about the night ferry.",
            "javascript:alert(1) is a link text that the page shows, and the ferry leaves the north pier late.",
        ]
        var blocks = [PageBlock(title, kind: .h, level: 1, zone: "main", inMain: true)]
        blocks += bad.map { PageBlock($0, zone: "main", inMain: true, links: 0) }
        let (id, _) = keep(e, out, ["url": "https://bad.example/x?q=\"><script>", "windowTitle": title])
        send(e, id, blocks, url: nil)
        let d = page(e)
        XCTAssertEqual(d.textState, .read)
        e.handle(.command(id: "w", lead: "where is", text: "onerror image", context: [:]))
        out.take()
        e.flushPages(force: true)
        for url in [e.keptCopyURL(d.id), e.pagesFolder.appendingPathComponent("kept.html"), e.searchPageURL] {
            let html = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(html.contains("<script"), url.lastPathComponent)
            XCTAssertFalse(html.contains("<img"), url.lastPathComponent)
            XCTAssertFalse(html.contains("<b>"), url.lastPathComponent)
            XCTAssertFalse(html.lowercased().contains("href=\"javascript:"), url.lastPathComponent)
            XCTAssertTrue(html.contains("&lt;b&gt;now&lt;/b&gt;"), url.lastPathComponent)
        }
        let copy = try String(contentsOf: e.keptCopyURL(d.id), encoding: .utf8)
        XCTAssertTrue(copy.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        XCTAssertTrue(copy.contains("&lt;img src=x onerror=alert(1)&gt;"))
        XCTAssertTrue(copy.contains("javascript:alert(1) is a link text"))
    }

    func testNoPageTextInTheLog() throws {
        let (e, out, _) = engine()
        let (id, _) = keep(e, out)
        send(e, id, Self.story)
        let log = try String(contentsOf: e.folder.appendingPathComponent("pa.log"), encoding: .utf8).lowercased()
        for w in ["council", "seven", "pier", "harbour", "varrow", "timetable"] {
            XCTAssertFalse(log.contains(w), w)
        }
        let events = try e.store!.db.query("SELECT * FROM event")
        XCTAssertFalse(events.description.lowercased().contains("council"))
    }

    /// 50 "keep this" commands: the first answer in 100 ms or less, slowest 1 in 10.
    func testFirstAnswerTime() {
        let (e, out, clock) = engine()
        var ms: [Double] = []
        for i in 0..<50 {
            clock.now = clock.now.addingTimeInterval(61)
            let start = Date()
            e.handle(.command(id: "k\(i)", lead: "keep this", text: "",
                              context: ["url": "https://varrow-news.example/p\(i)", "windowTitle": "Page \(i)"]))
            ms.append(Date().timeIntervalSince(start) * 1000)
            out.take()
        }
        let p90 = ms.sorted()[44]
        XCTAssertLessThanOrEqual(p90, 100)
    }

    func testNormalAddress() {
        XCTAssertEqual(Engine.normalPageAddress("https://a.example/p?utm_source=x&id=3&fbclid=z#c"), "https://a.example/p?id=3")
        XCTAssertEqual(Engine.normalPageAddress("https://a.example/p?gclid=1"), "https://a.example/p")
        XCTAssertEqual(Engine.groupNumber(1240), "1,240")
        XCTAssertEqual(Engine.groupNumber(800), "800")
        XCTAssertEqual(Engine.groupNumber(1234567), "1,234,567")
        XCTAssertEqual(Engine.siteName("https://www.example.com/a"), "example.com")
    }
}
