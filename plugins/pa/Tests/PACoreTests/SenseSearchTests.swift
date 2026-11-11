import Foundation
import XCTest
@testable import PACore

/// Phase 2, Q3: the index with numbers and "where is" by sense (build spec 7.6, 7.7). The tests use the hash
/// model, which has fixed numbers. All files and words are made-up.
final class SenseSearchTests: XCTestCase {
    func engine(model: Bool = true, folder: URL = tempFolder()) -> (Engine, MemoryOutput) {
        let out = MemoryOutput()
        let e = Engine(folder: folder, clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        if model { e.models = ModelHost(modelID: "hash-256-v1") { HashEmbedder() } }
        e.start()
        return (e, out)
    }

    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "", _ ctx: [String: String] = [:]) -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
        return out.take().last(where: { if case .answer(let re, _, _, _) = $0 { return re != nil } else { return false } })!
    }

    func file(_ name: String, _ text: String) -> URL {
        let url = tempFolder().appendingPathComponent(name)
        try! Data(text.utf8).write(to: url)
        return url
    }

    static let quote = "Quote from Harbour Ceramics for the floor tiles. The porcelain tiles cost 42 pounds per square metre. Delivery takes ten working days."

    func testKeptTextAndItemsGetNumbers() throws {
        let (e, out) = engine()
        let f = file("quote-tiles.txt", Self.quote)
        say(e, out, "keep this", "", ["document": f.path])
        say(e, out, "todo", "call the plumber about the boiler")
        let model = e.models!.modelID
        XCTAssertEqual(e.index!.vectorOwners(.passage, model: model).count, 1)
        XCTAssertEqual(e.index!.vectorOwners(.item, model: model).count, 1)
        XCTAssertEqual(e.index!.vectors(.item, model: model).first?.1.count, 256)
    }

    func testWhereIsFindsAPassageAndWritesTheSearchPage() throws {
        let (e, out) = engine()
        let f = file("quote-tiles.txt", Self.quote)
        say(e, out, "keep this", "", ["document": f.path])
        let a = say(e, out, "where is", "the porcelain price")
        guard case .answer(_, .list, "Found", let lines) = a else { return XCTFail("\(a)") }
        // A passage line: the title, then the first 80 characters of the passage.
        XCTAssertTrue(lines.first!.hasPrefix("quote-tiles.txt · Quote from Harbour Ceramics"), lines.first!)
        XCTAssertLessThanOrEqual(lines.first!.count, "quote-tiles.txt · ".count + 81)
        let page = try String(contentsOf: e.searchPageURL, encoding: .utf8)
        XCTAssertTrue(page.contains("<title>Search · PA</title>"))
        XCTAssertTrue(page.contains(f.path))
        XCTAssertTrue(e.targets().contains { $0.name == "search" && $0.open == e.searchPageURL.path })
    }

    func testFirstSearchLoadsTheModelForTheNext() throws {
        let (e, out) = engine()
        // The index already loaded the model. Unload it, as after 5 minutes with no use.
        e.models!.unload()
        XCTAssertFalse(e.models!.isLoaded)
        say(e, out, "todo", "order the green paint")
        e.models!.unload()
        say(e, out, "where is", "paint")
        // The search answered with keywords and loaded the model in the background (at once in tests).
        XCTAssertTrue(e.models!.isLoaded)
        let a = say(e, out, "where is", "paint")
        guard case .answer(_, .list, _, let lines) = a else { return XCTFail("\(a)") }
        XCTAssertEqual(lines.first, "order the green paint · to-do")
    }

    func testModelUnloadsWhenIdleAndAtStop() throws {
        let (e, out) = engine()
        say(e, out, "todo", "order the green paint")
        say(e, out, "where is", "paint")
        XCTAssertTrue(e.models!.isLoaded)
        XCTAssertFalse(e.models!.unloadIfIdle(now: Date(), after: 300))
        XCTAssertTrue(e.models!.unloadIfIdle(now: Date().addingTimeInterval(301), after: 300))
        XCTAssertFalse(e.models!.isLoaded)
        e.models!.preload()
        e.stop()
        XCTAssertFalse(e.models!.isLoaded)
    }

    func testANewModelBuildsTheNumbersAgain() throws {
        let folder = tempFolder()
        do {
            let (e, out) = engine(folder: folder)
            say(e, out, "todo", "order the green paint")
            try e.index!.putVectors(.item, [(99, [1, 0])], model: "old-model")
            e.stop()
        }
        let (e, _) = engine(folder: folder)
        XCTAssertTrue(e.index!.vectorOwners(.item, model: "old-model").isEmpty)
        XCTAssertEqual(e.index!.vectorOwners(.item, model: e.models!.modelID).count, 1)
    }

    func testDropDeletesTheNumbers() throws {
        let (e, out) = engine()
        let f = file("quote-tiles.txt", Self.quote)
        say(e, out, "keep this", "", ["document": f.path])
        say(e, out, "todo", "order the green paint")
        let model = e.models!.modelID
        say(e, out, "drop", "order the green paint")
        XCTAssertTrue(e.index!.vectorOwners(.item, model: model).isEmpty)
        let d = e.store!.doc(path: f.path)!
        e.forgetText(d.id)
        XCTAssertTrue(e.index!.vectorOwners(.passage, model: model).isEmpty)
    }

    func testNoModelUsesKeywordsOnly() throws {
        let (e, out) = engine(model: false)
        let f = file("quote-tiles.txt", Self.quote)
        say(e, out, "keep this", "", ["document": f.path])
        let a = say(e, out, "where is", "porcelain")
        guard case .answer(_, .list, _, let lines) = a else { return XCTFail("\(a)") }
        XCTAssertTrue(lines.first!.hasPrefix("quote-tiles.txt · "))
        XCTAssertEqual(try e.index!.db.query("SELECT COUNT(*) FROM vector").first?.first?.int, 0)
    }

    func testABrokenModelFallsBackToKeywords() throws {
        struct Broken: Error {}
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        e.models = ModelHost(modelID: "broken") { throw Broken() }
        e.start()
        say(e, out, "todo", "order the green paint")
        let a = say(e, out, "where is", "paint")
        guard case .answer(_, .list, _, let lines) = a else { return XCTFail("\(a)") }
        XCTAssertEqual(lines.first, "order the green paint · to-do")
        XCTAssertTrue(e.models!.isFailed)
    }

    func testCutStopsAtAWordEnd() {
        XCTAssertEqual(Engine.cut("short text", 80), "short text")
        let long = String(repeating: "word ", count: 40)
        let c = Engine.cut(long, 80)
        XCTAssertTrue(c.hasSuffix("word…"), c)
        XCTAssertLessThanOrEqual(c.count, 81)
    }
}

extension SenseSearchTests {
    func testTheFloorDropsWeakResultsByNumbers() throws {
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        let host = ModelHost(modelID: "hash-256-v1") { HashEmbedder() }
        host.rules = ModelRules(projectA: 1, projectB: 1, duplicateC: 1, searchFloor: 0.99)
        e.models = host
        e.start()
        say(e, out, "todo", "order the green paint")
        say(e, out, "where is", "passport")
        // A word with no keyword match and no strong number match: nothing found.
        let a = say(e, out, "where is", "passport")
        XCTAssertEqual(a.text, "Nothing found for passport.")
    }
}
