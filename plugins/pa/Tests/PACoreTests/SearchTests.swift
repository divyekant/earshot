import XCTest
@testable import PACore

/// Phase 2, Q1: the parts of the search and the bench (phase 2 build spec, section 6). All data is made-up.
final class SearchTests: XCTestCase {
    static var phase2: URL {
        Bundle.module.url(forResource: "phase2", withExtension: nil, subdirectory: "Fixtures")!
    }

    func testSentencesKeepTheText() {
        let text = "The hob takes 7.4 kilowatts. Ravi will run a new cable! Is it fine? \"Yes,\" he said.\nA heading\nThe end."
        let s = TextCut.sentences(text)
        XCTAssertEqual(s, ["The hob takes 7.4 kilowatts.", "Ravi will run a new cable!", "Is it fine?",
                           "\"Yes,\" he said.", "A heading", "The end."])
        for x in s { XCTAssertTrue(text.contains(x)) }
    }

    func testPassagesOverlapByOneSentence() {
        let sentence = (1...20).map { "word\($0)" }.joined(separator: " ") + "."
        let text = (1...10).map { _ in sentence.replacingOccurrences(of: "word1 ", with: "Word1 ") }.joined(separator: " ")
        let p = TextCut.passages(text, page: 3)
        XCTAssertGreaterThan(p.count, 1)
        XCTAssertEqual(p.first?.page, 3)
        for x in p { XCTAssertLessThanOrEqual(x.text.split(separator: " ").count, 120) }
        // The last sentence of one passage is the first sentence of the next.
        let last = TextCut.sentences(p[0].text).last!
        XCTAssertEqual(TextCut.sentences(p[1].text).first, last)
        XCTAssertEqual(p.map(\.position), Array(0..<p.count))
    }

    func testLongSentenceIsOnePassage() {
        let long = (1...300).map { "w\($0)" }.joined(separator: " ") + "."
        XCTAssertEqual(TextCut.passages(long).count, 1)
    }

    func testFusionCountsBothLists() {
        // "b" is second in both lists, so it is above "a" (first in one list only).
        XCTAssertEqual(Fusion.merge([["a", "b"], ["c", "b"]]).first, "b")
        XCTAssertEqual(Set(Fusion.merge([["a"], ["c"]])), ["a", "c"])
        XCTAssertEqual(Fusion.unique(["x", "y", "x"]), ["x", "y"])
    }

    func testKeywordIndexFindsAnyWord() throws {
        let db = try SQLite(path: ":memory:")
        let k = try KeywordIndex(db: db, table: "t")
        try k.add(1, "Quote for the floor tiles")
        try k.add(2, "Letter from the plumber")
        XCTAssertEqual(k.search("where is the quote for the tiles", limit: 5).first, 1)
        XCTAssertEqual(k.search("plumbers", limit: 5), [2])
        try k.remove(2)
        XCTAssertEqual(k.search("plumber", limit: 5), [])
        XCTAssertEqual(k.search("where is the", limit: 5), [])
    }

    func testHashEmbedderIsStable() throws {
        let e = HashEmbedder()
        let a = try e.embed(["call the tile shop"], kind: .query)[0]
        let b = try e.embed(["call the tile shop"], kind: .passage)[0]
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 256)
        XCTAssertGreaterThan(Vectors.dot(a, try e.embed(["call the tile shops"], kind: .query)[0]), 0.9)
        XCTAssertEqual(Vectors.cut(a, to: 64).count, 64)
    }

    func testProjectRuleNeedsAGap() {
        let r = ProjectRule(a: 0.5, b: 0.1)
        XCTAssertEqual(r.propose([("kitchen", 0.8), ("taxes", 0.6)]), "kitchen")
        XCTAssertNil(r.propose([("kitchen", 0.8), ("taxes", 0.75)]))
        XCTAssertNil(r.propose([("kitchen", 0.4), ("taxes", 0.1)]))
        let cases: [(scores: [(String, Float)], truth: String)] = [
            ([("k", 0.9), ("t", 0.2)], "k"), ([("k", 0.7), ("t", 0.1)], "t"), ([("k", 0.3), ("t", 0.1)], "none"),
        ]
        let fit = ProjectRule.fit(cases, maxWrong: 0)
        XCTAssertEqual(fit.count(cases).proposals, 1)
        XCTAssertEqual(fit.count(cases).wrong, 0)
    }

    func testMainPointsAreSentencesOfTheText() throws {
        let fx = try BenchFixtures.load(Self.phase2)
        for p in fx.points {
            let sel = try MainPoints.select(p.text, embedder: HashEmbedder())
            XCTAssertEqual(sel.count, 5, p.name)
            for s in sel { XCTAssertTrue(p.text.contains(s), "\(p.name): a selected sentence is not in the text") }
            // In the order of the document.
            let at = sel.map { p.text.range(of: $0)!.lowerBound }
            XCTAssertEqual(at, at.sorted(), p.name)
        }
    }

    /// The fixtures of 6.3 have the counts of the spec. The holdout files do not change after a score (rule 5).
    func testFixturesHaveTheCountsOfTheSpec() throws {
        let fx = try BenchFixtures.load(Self.phase2)
        XCTAssertEqual(fx.projects.count, 10)
        XCTAssertEqual(fx.docs.count, 40)
        XCTAssertEqual(fx.items.count, 120)
        let keys = Set(fx.docs.map(\.key) + fx.items.map(\.key))
        for set in ["dev", "holdout"] {
            let q = fx.questions[set]!
            XCTAssertEqual(q.count, 100)
            XCTAssertGreaterThanOrEqual(q.filter(\.other).count, 40)
            for x in q { XCTAssertTrue(keys.contains(x.target), x.target) }
            let c = fx.captures[set]!
            XCTAssertEqual(c.count, 100)
            XCTAssertEqual(c.filter { $0.project == "none" }.count, 30)
        }
        for d in fx.docs {
            let n = d.text.split(whereSeparator: { $0.isWhitespace }).count
            XCTAssertTrue((150...600).contains(n), "\(d.key): \(n) words")
        }
        XCTAssertEqual(fx.points.count, 10)
        for p in fx.points {
            XCTAssertEqual(p.marks.count, 3, p.name)
            for m in p.marks { XCTAssertTrue(MainPoints.candidates(p.text).contains(m), "\(p.name): a mark is not a sentence") }
        }
        XCTAssertEqual(fx.pairs.count, 40)
    }

    /// The bench runs with the hash model (no macOS model on Linux). It prints the table for the CI log.
    func testBenchRunsWithTheHashModel() throws {
        let fx = try BenchFixtures.load(Self.phase2)
        let r = try EmbedBench(fixtures: fx, embedder: HashEmbedder()).run()
        XCTAssertGreaterThan(r.searchHoldoutKeyword, 50)
        for line in EmbedBench.table(r).split(separator: "\n") { print("MARK bench hash \(line)") }
    }
}
