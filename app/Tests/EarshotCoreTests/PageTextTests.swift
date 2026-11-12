@testable import EarshotCore
import XCTest

/// The context key "pageText": the reply lines and the asks (R-PL-2, R-PL-5, docs/PLUGINS.md 5.3). Made-up pages only.
final class PageTextTests: XCTestCase {
    private func decode(_ lines: [Data]) throws -> [PageTextReply] {
        try lines.map { line in
            XCTAssertEqual(line.last, 0x0A)
            XCTAssertLessThanOrEqual(line.count, PageText.maxLineBytes)
            return try JSONDecoder().decode(PageTextReply.self, from: line.dropLast())
        }
    }

    func testOneSmallPageIsOneLine() throws {
        let blocks = [PageBlock(t: "Fox facts", k: "h", level: 1, zone: "main", inMain: true, links: 0),
                      PageBlock(t: "The fox is red.", zone: "main", inMain: true, links: 0)]
        let replies = try decode(PageText.lines(re: "c1", url: "https://fox.example/a", title: "Fox", blocks: blocks, complete: true))
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies[0].part, 1)
        XCTAssertEqual(replies[0].of, 1)
        XCTAssertEqual(replies[0].complete, true)
        XCTAssertEqual(replies[0].url, "https://fox.example/a")
        XCTAssertEqual(replies[0].title, "Fox")
        XCTAssertEqual(replies[0].blocks, blocks)
        XCTAssertNil(replies[0].error)
    }

    func testAnEmptyPageIsOneLineWithNoBlocks() throws {
        let replies = try decode(PageText.lines(re: "c1", url: nil, title: nil, blocks: [], complete: true))
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies[0].blocks, [])
    }

    /// A large page goes in parts. Each line is under the limit, the blocks stay in order, and only part 1 has the
    /// address and the title.
    func testALargePageGoesInParts() throws {
        let blocks = (0..<2_000).map { PageBlock(t: "Paragraph \($0) " + String(repeating: "word ", count: 30), k: "p") }
        let replies = try decode(PageText.lines(re: "c2", url: "https://fox.example/b", title: "Long", blocks: blocks, complete: false))
        XCTAssertGreaterThan(replies.count, 1)
        for (i, r) in replies.enumerated() {
            XCTAssertEqual(r.re, "c2")
            XCTAssertEqual(r.part, i + 1)
            XCTAssertEqual(r.of, replies.count)
            XCTAssertEqual(r.complete, false)
            XCTAssertEqual(r.url, i == 0 ? "https://fox.example/b" : nil)
            XCTAssertEqual(r.title, i == 0 ? "Long" : nil)
        }
        XCTAssertEqual(replies.flatMap { $0.blocks ?? [] }, blocks)
    }

    /// A block longer than the block limit (a text area) becomes more blocks of the same kind.
    func testALongBlockIsCut() throws {
        let long = String(repeating: "a", count: PageText.maxBlockCharacters * 2 + 10)
        let replies = try decode(PageText.lines(re: "c3", url: nil, title: nil, blocks: [PageBlock(t: long, k: "pre")], complete: true))
        let got = replies.flatMap { $0.blocks ?? [] }
        XCTAssertEqual(got.map(\.t.count), [PageText.maxBlockCharacters, PageText.maxBlockCharacters, 10])
        XCTAssertEqual(Set(got.map(\.k)), ["pre"])
        XCTAssertEqual(got.map(\.t).joined(), long)
    }

    /// Characters that JSON escapes (quotes, new lines, other scripts) still fit.
    func testEscapedTextFits() throws {
        let blocks = (0..<3_000).map { PageBlock(t: "\"\($0)\"\n\\ ünïcödé 狐狸 " + String(repeating: "\u{1}", count: 20)) }
        let replies = try decode(PageText.lines(re: "c4", url: nil, title: nil, blocks: blocks, complete: true))
        XCTAssertEqual(replies.flatMap { $0.blocks ?? [] }, blocks)
    }

    func testErrorLine() throws {
        let line = PageText.errorLine(re: "c5", "not a web page")
        XCTAssertEqual(line.last, 0x0A)
        let reply = try JSONDecoder().decode(PageTextReply.self, from: line.dropLast())
        XCTAssertEqual(reply.type, "pageText")
        XCTAssertEqual(reply.re, "c5")
        XCTAssertEqual(reply.error, "not a web page")
        XCTAssertNil(reply.blocks)
    }

    func testAsks() {
        let asks = PageTextAsks()
        let t0 = Date()
        asks.sent(id: "c1", pluginID: "pa", url: "https://fox.example", at: t0)
        XCTAssertEqual(asks.ask(re: "c9", pluginID: "pa", at: t0), .failure(.init("no command with this id")))
        XCTAssertEqual(asks.ask(re: nil, pluginID: "pa", at: t0), .failure(.init("no command with this id")))
        XCTAssertEqual(asks.ask(re: "c1", pluginID: "other", at: t0), .failure(.init("no command with this id")))
        guard case .success(let c) = asks.ask(re: "c1", pluginID: "pa", at: t0.addingTimeInterval(1)) else { return XCTFail("refused") }
        XCTAssertEqual(c.id, "c1")
        XCTAssertEqual(c.url, "https://fox.example")
        XCTAssertEqual(asks.ask(re: "c1", pluginID: "pa", at: t0.addingTimeInterval(2)), .failure(.init("one ask for each command")))
        asks.sent(id: "c2", pluginID: "pa", url: nil, at: t0)
        XCTAssertEqual(asks.ask(re: "c2", pluginID: "pa", at: t0.addingTimeInterval(PageText.askSeconds + 1)), .failure(.init("too late")))
    }

    /// Old commands go, so that the list stays small.
    func testOldCommandsGo() {
        let asks = PageTextAsks()
        let t0 = Date()
        asks.sent(id: "old", pluginID: "pa", url: nil, at: t0)
        asks.sent(id: "new", pluginID: "pa", url: nil, at: t0.addingTimeInterval(PageText.askSeconds * 7))
        XCTAssertEqual(asks.ask(re: "old", pluginID: "pa", at: t0), .failure(.init("no command with this id")))
    }

    /// A page that is still loading: earshot reads again after 1 s, for 3 s at most (W1 follow-up).
    func testSettle() {
        let few = [PageBlock(t: "Loading")]
        let many = [PageBlock(t: String(repeating: "word ", count: PageText.settleWords))]
        var reads = 0, waits: [Double] = []
        var got = PageText.settled(read: { () -> [PageBlock] in reads += 1; return reads < 3 ? few : many },
                                   blocks: { $0 }, wait: { waits.append($0) })
        XCTAssertEqual(got, many)
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(waits, [1, 1])
        // Never enough words: 4 reads in 3 s, then the last read.
        reads = 0; waits = []
        got = PageText.settled(read: { reads += 1; return few }, blocks: { $0 }, wait: { waits.append($0) })
        XCTAssertEqual(got, few)
        XCTAssertEqual(reads, 4)
        XCTAssertEqual(waits.reduce(0, +), PageText.settleSeconds)
        // An error or a full page: one read only.
        reads = 0
        _ = PageText.settled(read: { reads += 1; return few }, blocks: { _ in nil }, wait: { _ in XCTFail("waited") })
        XCTAssertEqual(reads, 1)
        reads = 0
        _ = PageText.settled(read: { reads += 1; return many }, blocks: { $0 }, wait: { _ in XCTFail("waited") })
        XCTAssertEqual(reads, 1)
    }
}
