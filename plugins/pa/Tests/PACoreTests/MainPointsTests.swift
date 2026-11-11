import Foundation
import XCTest
@testable import PACore

/// Phase 2, Q5: "main points" (build spec 8.4). The tests use the hash model and the made-up documents of the
/// fixtures.
final class MainPointsTests: XCTestCase {
    static var points: URL {
        Bundle.module.url(forResource: "phase2", withExtension: nil, subdirectory: "Fixtures")!.appendingPathComponent("points")
    }

    func engine(model: Bool = true) -> (Engine, MemoryOutput) {
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        if model { e.models = ModelHost(modelID: "hash-256-v1") { HashEmbedder() } }
        e.start()
        e.settings.projectFocusMinutes = 0
        return (e, out)
    }

    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "", _ ctx: [String: String] = [:]) -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
        return out.take().last(where: { if case .answer(let re, _, _, _) = $0 { return re != nil } else { return false } })!
    }

    func firstPointsFile() throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: Self.points, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }.sorted { $0.path < $1.path }
        return files[0]
    }

    func testMainPointsOfThisAreSentencesOfTheDocument() throws {
        let (e, out) = engine()
        let f = try firstPointsFile()
        let text = try String(contentsOf: f, encoding: .utf8)
        let a = say(e, out, "main points", "of this", ["document": f.path])
        guard case .answer(_, .list, let title, let lines) = a else { return XCTFail("\(a)") }
        XCTAssertEqual(title, "Main points · " + f.lastPathComponent)
        XCTAssertEqual(lines.count, 5)
        for l in lines { XCTAssertLessThanOrEqual(l.count, Engine.pointLine + 1) }
        // The page has the full sentences: each one is in the document, character for character.
        let page = try String(contentsOf: e.mainPointsPageURL, encoding: .utf8)
        let sentences = MainPoints.candidates(text).filter { page.contains(Engine.escape($0)) }
        XCTAssertEqual(sentences.count, 5)
        for s in sentences { XCTAssertTrue(text.contains(s)) }
        // The document in front was not kept: the command kept it.
        XCTAssertEqual(e.store!.doc(path: f.path)?.textState, .read)
        XCTAssertTrue(e.targets().contains { $0.name == "main points" })
    }

    func testMainPointsByWordsAndByNumber() throws {
        let (e, out) = engine()
        let f = try firstPointsFile()
        say(e, out, "keep this", "", ["document": f.path])
        let words = MainPoints.candidates(try String(contentsOf: f, encoding: .utf8))[0].split(separator: " ").prefix(4).joined(separator: " ")
        let a = say(e, out, "main points", "of " + words)
        XCTAssertEqual(a.text, "Main points · " + f.lastPathComponent)
        // "main points 1" after a search list.
        say(e, out, "where is", words)
        let b = say(e, out, "main points", "1")
        XCTAssertEqual(b.text, "Main points · " + f.lastPathComponent)
    }

    func testNoTextAndNoModel() throws {
        let (e, out) = engine()
        XCTAssertEqual(say(e, out, "main points").text, "No document here. Nothing to show.")
        let (e2, out2) = engine(model: false)
        let f = try firstPointsFile()
        XCTAssertEqual(say(e2, out2, "main points", "of this", ["document": f.path]).text,
                       "Main points need the search model. It is not installed.")
    }
}
