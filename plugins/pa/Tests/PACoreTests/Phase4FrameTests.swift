import Foundation
@testable import PACore
import XCTest

/// Phase 4, W2: the manifest, the setting, the store and the page text messages (spec section 9.1).
final class Phase4FrameTests: XCTestCase {
    func testManifest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("plugin.json")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(o["version"] as? String, "0.4.0")
        XCTAssertTrue((o["context"] as? [String] ?? []).contains("pageText"))
        XCTAssertEqual(o["network"] as? [String], [], "no network code (spec rule 13)")
    }

    func testSettingDefaults() throws {
        XCTAssertTrue(PASettings().pageText)
        XCTAssertTrue(PASettings().pagePoints)
        let old = try JSONDecoder().decode(PASettings.self, from: Data(#"{"silenceDays": 5}"#.utf8))
        XCTAssertTrue(old.pageText, "a settings file of phase 3 gets the default")
        let off = try JSONDecoder().decode(PASettings.self, from: Data(#"{"pageText": false}"#.utf8))
        XCTAssertFalse(off.pageText)
    }

    func testMigrationAndDocColumns() throws {
        let url = tempFolder().appendingPathComponent("pa.sqlite")
        do {
            let s = try Store(url: url)
            try s.db.exec("ALTER TABLE doc DROP COLUMN text_at; ALTER TABLE doc DROP COLUMN text_words; PRAGMA user_version = 4;")
        }
        let store = try Store(url: url)
        XCTAssertEqual(try store.db.query("PRAGMA user_version").first?.first?.int, 5)
        var d = Doc(address: "https://example.org/a", title: "Made-up page", app: "Safari", projectID: nil, createdAt: Date(timeIntervalSince1970: 1000))
        d.textState = .partial
        d.textAt = Date(timeIntervalSince1970: 2000)
        d.textWords = 1240
        let id = try store.insertDoc(d)
        let back = try XCTUnwrap(store.doc(id))
        XCTAssertEqual(back.textState, .partial)
        XCTAssertEqual(back.textAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(back.textWords, 1240)
        var u = back
        u.textState = .changed
        u.textWords = nil
        try store.updateDoc(u, event: "page-text", at: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(store.doc(id)?.textState, .changed)
        XCTAssertNil(store.doc(id)?.textWords)
    }

    func testBlockNamesAndUnknownKeys() throws {
        let a = PageBlock.from(["t": "Heat pumps", "k": "h", "level": 1, "zone": "main", "inMain": true, "links": 0, "extra": 3])
        XCTAssertEqual(a, PageBlock("Heat pumps", kind: .h, level: 1, zone: "main", inMain: true, links: 0))
        let b = PageBlock.from(["text": "A paragraph.", "kind": "p", "linkShare": 0.25])
        XCTAssertEqual(b?.links, 0.25)
        XCTAssertEqual(b?.kind, .p)
        XCTAssertEqual(PageBlock.from(["t": "x", "k": "weird"])?.kind, .p, "an unknown kind is a paragraph")
        XCTAssertNil(PageBlock.from(["k": "p"]), "a block with no text")
    }

    func testPartsJoinInOrder() throws {
        func line(_ s: String) -> Incoming? { Incoming.parse(Data(s.utf8)) }
        guard case .pageText(let p2)? = line(#"{"type":"pageText","re":"c1","part":2,"of":2,"complete":false,"blocks":[{"t":"second"}]}"#),
              case .pageText(let p1)? = line(#"{"type":"pageText","re":"c1","part":1,"of":2,"complete":false,"url":"https://example.org/a","title":"A","blocks":[{"t":"first","k":"h","level":1}]}"#) else {
            return XCTFail("no page text message")
        }
        var a = PageTextAssembler()
        XCTAssertNil(a.add(p2))
        let page = try XCTUnwrap(a.add(p1))
        XCTAssertEqual(page.blocks.map(\.text), ["first", "second"])
        XCTAssertEqual(page.url, "https://example.org/a")
        XCTAssertEqual(page.title, "A")
        XCTAssertFalse(page.complete)
        XCTAssertEqual(page.wordCount, 2)
        guard case .pageText(.error(let re, let reason))? = line(#"{"type":"pageText","re":"c2","error":"the page changed"}"#) else {
            return XCTFail("no error message")
        }
        XCTAssertEqual(re, "c2")
        XCTAssertEqual(reason, "the page changed")
    }

    func testAskLine() throws {
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Outgoing.askPageText(re: "c9").line()) as? [String: String])
        XCTAssertEqual(o, ["type": "pageText", "re": "c9"])
    }

    func testFixtureSource() throws {
        let folder = tempFolder()
        let json = #"{"browser":"com.example","complete":true,"ms":12.5,"url":"file:///a.html","blocks":[{"t":"Title","k":"h","level":1,"zone":"main","inMain":true},{"t":"Body text here.","k":"p","links":0.1}]}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("a.json"))
        let src = PageFixtureSource(folder: folder)
        XCTAssertEqual(src.names, ["a"])
        let page = try XCTUnwrap(src.page("a"))
        XCTAssertEqual(page.blocks.count, 2)
        XCTAssertEqual(page.blocks[0].level, 1)
        XCTAssertEqual(page.wordCount, 4)
    }

    func testEngineLogsNoPageText() throws {
        let folder = tempFolder()
        let e = Engine(folder: folder, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)), output: MemoryOutput())
        e.receive(Data(#"{"type":"pageText","re":"c1","part":1,"of":1,"complete":true,"blocks":[{"t":"MADEUP-SECRET-WORDS in a page"}]}"#.utf8))
        let log = (try? String(contentsOf: folder.appendingPathComponent("pa.log"), encoding: .utf8)) ?? ""
        XCTAssertFalse(log.contains("MADEUP-SECRET-WORDS"))
    }
}
