import Foundation
import XCTest
@testable import FootnoteCore

/// Pages and targets (build spec 11.1, 11.2). Made-up items only.
final class PagesTests: XCTestCase {
    func say(_ e: Engine, _ lead: String, _ text: String, _ ctx: [String: String] = [:]) {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
    }

    func testPagesAndTargets() throws {
        let (e, out, clock) = makeEngine()
        e.handle(.hello(contract: 1))
        guard case .targets(let first) = out.take().first(where: { if case .targets = $0 { return true }; return false })! else { return XCTFail() }
        XCTAssertEqual(first.map(\.name), ["today", "all open", "flags", "kept pages"])
        say(e, "new project", "kitchen")
        let msgs = out.take()
        let targets = msgs.compactMap { m -> [Target]? in if case .targets(let t) = m { return t }; return nil }.last!
        XCTAssertEqual(targets.last?.name, "Kitchen")
        XCTAssertEqual(targets.last?.kind, "project")
        XCTAssertTrue(targets.last!.open!.hasSuffix("pages/project-kitchen.html"))

        say(e, "todo", "call the <b>tile</b> shop & co for kitchen")
        say(e, "remind me", "to call the plumber at 5")
        say(e, "keep this", "for kitchen", ["windowTitle": "Tile offer", "url": "https://example.com/offer?a=1&b=2"])
        clock.advance(minutes: 0.05)
        e.tick()
        let today = try String(contentsOf: e.pagesFolder.appendingPathComponent("today.html"), encoding: .utf8)
        XCTAssertTrue(today.contains("call the plumber"))
        XCTAssertTrue(today.contains("17:00"))
        let kitchen = try String(contentsOf: e.pagesFolder.appendingPathComponent("project-kitchen.html"), encoding: .utf8)
        XCTAssertTrue(kitchen.contains("call the &lt;b&gt;tile&lt;/b&gt; shop &amp; co"))
        XCTAssertFalse(kitchen.contains("<b>tile"))
        XCTAssertTrue(kitchen.contains("href=\"https://example.com/offer?a=1&amp;b=2\""))
        for page in [today, kitchen] {
            XCTAssertFalse(page.contains("<script"))
            XCTAssertFalse(page.contains("<img"))
            XCTAssertFalse(page.contains("@import"))
            XCTAssertFalse(page.contains("<link"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: e.pagesFolder.appendingPathComponent("all-open.html").path))
        // earshot shows index.html in its window and panel: it is the Today page.
        let index = try String(contentsOf: e.pagesFolder.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertEqual(index, today)
    }

    /// board.json holds the same lists as data for earshot (earshot docs/PLUGINS.md 5.5): tabs, rows and the panel.
    func testBoardHoldsTheLists() throws {
        let (e, _, clock) = makeEngine()
        e.handle(.hello(contract: 1))
        say(e, "new project", "kitchen")
        say(e, "todo", "order the tiles for kitchen")
        say(e, "remind me", "to call the plumber at 5")
        clock.advance(minutes: 0.05)
        e.tick()
        let data = try Data(contentsOf: e.pagesFolder.appendingPathComponent("board.json"))
        let board = try JSONDecoder().decode(BoardFile.self, from: data)
        XCTAssertEqual(board.version, 1)
        XCTAssertEqual(board.tabs.map(\.id), ["today", "all", "flags", "projects", "kept"])
        XCTAssertEqual(board.settingsTab, "Rules")
        let today = board.tabs[0]
        let rows = today.sections.compactMap(\.rows).flatMap { $0 }
        XCTAssertTrue(rows.contains { $0.text.contains("call the plumber") && $0.when?.contains("17:00") == true && $0.mark == "todo" })
        XCTAssertEqual(today.sections.last?.title, "The last 7 days")
        XCTAssertTrue(board.panel!.rows.contains { $0.text.contains("call the plumber") })
        XCTAssertLessThanOrEqual(board.panel!.rows.count, BoardFile.panelRows)
        let projects = board.tabs[3].sections[0].rows ?? []
        XCTAssertEqual(projects.map(\.text), ["Kitchen"])
        XCTAssertEqual(projects.first?.open, "project-kitchen.html")
        let all = board.tabs[1].sections.map(\.title)
        XCTAssertTrue(all.contains("Kitchen"))
    }

    func testTodayLine() {
        XCTAssertEqual(Engine.todayLine(late: 1, today: 1, tomorrow: 2), "1 late, 1 for today, 2 for tomorrow")
        XCTAssertEqual(Engine.todayLine(late: 0, today: 0, tomorrow: 0), "Nothing late and nothing for today")
    }

    func testPagesAtMostOnceASecond() throws {
        let (e, _, clock) = makeEngine()
        e.handle(.hello(contract: 1))
        let url = e.pagesFolder.appendingPathComponent("today.html")
        say(e, "remind me", "to call the plumber at 5")
        // Same second as the hello: the write waits.
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("plumber"))
        clock.advance(minutes: 1.0 / 60)
        e.tick()
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("plumber"))
    }
}
