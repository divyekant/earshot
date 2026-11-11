import Foundation
import XCTest
@testable import PACore

/// Pages and targets (build spec 11.1, 11.2). Made-up items only.
final class PagesTests: XCTestCase {
    func say(_ e: Engine, _ lead: String, _ text: String, _ ctx: [String: String] = [:]) {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: ctx))
    }

    func testPagesAndTargets() throws {
        let (e, out, clock) = makeEngine()
        e.handle(.hello(contract: 1))
        guard case .targets(let first) = out.take().first(where: { if case .targets = $0 { return true }; return false })! else { return XCTFail() }
        XCTAssertEqual(first.map(\.name), ["today", "all open"])
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
