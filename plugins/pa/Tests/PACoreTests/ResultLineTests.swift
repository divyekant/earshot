import Foundation
import XCTest
@testable import PACore

/// Phase 2 follow-up, R4 (phase 2 build spec, section 9, "Words only from documents"): each result line of
/// "where is" is made only of a document title, a part of a passage or of an item, and fixed labels.
/// The test uses the made-up corpus of phase 2 and the hash model.
final class ResultLineTests: XCTestCase {
    static let phase2 = Bundle.module.url(forResource: "phase2", withExtension: nil, subdirectory: "Fixtures")!

    static func flat(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }

    func testTwoHundredResultLinesHoldOnlyWordsOfTheOwner() throws {
        let fx = try BenchFixtures.load(Self.phase2)
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out, textReader: FileTextReader())
        e.models = ModelHost(modelID: "hash-256-v1") { HashEmbedder() }
        e.start()
        e.settings.projectFocusMinutes = 0
        func say(_ lead: String, _ text: String, _ ctx: [String: String] = [:]) -> Outgoing? {
            e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
            return out.take().last(where: { if case .answer(let re, _, _, _) = $0 { return re != nil } else { return false } })
        }
        // The owner's words: the projects, the kept files and the items.
        for p in fx.projects { _ = say("new project", p.name) }
        let folder = tempFolder()
        var titles = Set<String>()
        var texts: [String] = []
        for d in fx.docs {
            let name = d.key.replacingOccurrences(of: "/", with: "-") + ".txt"
            let url = folder.appendingPathComponent(name)
            try Data(d.text.utf8).write(to: url)
            let project = fx.projects.first { $0.id == d.project }!.name
            _ = say("keep this", "for \(project)", ["document": url.path])
            titles.insert(name)
            texts.append(Self.flat(d.text))
        }
        for it in fx.items {
            let project = fx.projects.first { $0.id == it.project }!.name
            _ = say("todo", "\(it.title) for \(project)")
            texts.append(Self.flat(it.title))
        }
        let labels: Set<String> = ["to-do", "reminder", "note", "to-do, done", "reminder, done", "note, done", "document", "project"]
        let projectNames = Set(fx.projects.map(\.name))

        var lines: [String] = []
        for q in (fx.questions["dev"] ?? []) + (fx.questions["holdout"] ?? []) where lines.count < 200 {
            guard case .answer(_, _, "Found", let found)? = say("where is", q.words) else { continue }
            lines += found
        }
        lines = Array(lines.prefix(200))
        XCTAssertEqual(lines.count, 200, "the questions gave fewer than 200 result lines")
        var bad: [String] = []
        for line in lines {
            for part in line.components(separatedBy: " · ") {
                let p = part.hasSuffix("…") ? String(part.dropLast()) : part
                let ok = titles.contains(p) || labels.contains(p) || projectNames.contains(p)
                    || projectNames.contains(where: { p == $0 + "?" })
                    || (p.hasPrefix("p. ") && Int(p.dropFirst(3)) != nil)
                    || texts.contains { $0.contains(p) }
                if !ok { bad.append(part) }
            }
        }
        XCTAssertEqual(bad, [], "parts of result lines that are not words of the owner or fixed labels")
        print("MARK words only from documents: \(lines.count) result lines, \(bad.count) parts not from the owner's words or labels")
    }
}
