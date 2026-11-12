import Foundation
@testable import PACore
import XCTest

/// The steps of the main text rule (spec section 8) on small block lists. These lists test the logic of each step;
/// the numbers of E12 come from blocks of the real read (spec 7.1).
final class MainTextTests: XCTestCase {
    func para(_ n: Int, _ word: String = "word", zone: String? = nil, inMain: Bool? = nil, links: Double? = 0) -> PageBlock {
        PageBlock(Array(repeating: word, count: n).joined(separator: " ") + ".", zone: zone, inMain: inMain, links: links)
    }

    func testStep1UsesMainWhenItHasEnoughWords() {
        let blocks = [para(10, "menu", zone: "nav"), para(160, "body", zone: "main", inMain: true),
                      para(20, "aside", zone: "aside", inMain: true), para(30, "foot", zone: "footer")]
        let r = MainText.select(blocks, variant: .zones)
        XCTAssertEqual(r.blocks.count, 1)
        XCTAssertEqual(r.words, 160)
    }

    func testStep2WithoutMain() {
        let blocks = [para(10, "menu", zone: "banner"), para(60, "body"), para(30, "foot", zone: "footer")]
        let r = MainText.select(blocks, variant: .zones)
        XCTAssertEqual(r.words, 60)
    }

    func testStep3LinksShortBlocksAndHeadings() {
        let blocks = [
            PageBlock("Title of the page", kind: .h, level: 1),
            para(40), PageBlock("Ok then", links: 0), para(40),
            para(20, "link", links: 0.9),
            PageBlock("Empty part", kind: .h, level: 2),
            PageBlock("Share", links: 0),
            PageBlock("Kept part", kind: .h, level: 2), para(30),
        ]
        let r = MainText.select(blocks, variant: .full)
        XCTAssertEqual(r.blocks.map(\.text).filter { !$0.hasPrefix("word") },
                       ["Title of the page", "Ok then", "Kept part"])
    }

    func testStep3DropsCopies() {
        let blocks = [PageBlock("Rules", kind: .h, level: 1), para(60, "rule"), PageBlock("Rules", kind: .h, level: 1),
                      para(60, "rule")]
        let r = MainText.select(blocks, variant: .full)
        XCTAssertEqual(r.blocks.filter { $0.text.hasPrefix("rule") }.count, 1)
        // The second heading has no kept text below it, so it goes too.
        XCTAssertEqual(r.blocks.filter { $0.text == "Rules" }.count, 1)
    }

    func testStep4EndWords() {
        let blocks = [PageBlock("Story", kind: .h, level: 1), para(60), PageBlock("Comments (3)", kind: .h, level: 2),
                      para(20, "comment"), para(20, "comment"), PageBlock("Next part", kind: .h, level: 2), para(10, "more")]
        let r = MainText.select(blocks, variant: .full)
        XCTAssertFalse(r.blocks.contains { $0.text.hasPrefix("comment") })
        XCTAssertTrue(r.blocks.contains { $0.text.hasPrefix("more") })
    }

    func testStep5NoText() {
        XCTAssertTrue(MainText.select([para(30)], variant: .full).noText)
        XCTAssertFalse(MainText.select([para(60)], variant: .full).noText)
    }

    func testVariantCKeepsAll() {
        let blocks = [para(10, zone: "nav", links: 1), para(5)]
        XCTAssertEqual(MainText.select(blocks, variant: .all).blocks.count, 2)
    }

    func testPassagesStayInSections() {
        let blocks = [PageBlock("Part one", kind: .h, level: 2), para(100, "alpha"), PageBlock("Part two", kind: .h, level: 2), para(30, "beta")]
        let ps = PageCut.passages(blocks).passages
        XCTAssertFalse(ps.contains { $0.text.contains("alpha") && $0.text.contains("beta") })
        let front = PageCut.passages(blocks, headingFront: true).passages
        XCTAssertTrue(front.last?.text.hasPrefix("Part two") ?? false)
    }

    func testScoreNumbers() {
        var l = PageBench.Labels()
        l.main = PageBench.multiset("the ferry stays")
        l.neutral = PageBench.multiset("by odile")
        let s = PageBench.score("The ferry by Odile menu", l)
        XCTAssertEqual(s.found, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(s.noise, 1.0 / 5.0, accuracy: 0.001)
    }
}
