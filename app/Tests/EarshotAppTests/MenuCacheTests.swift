@testable import EarshotApp
import EarshotCore
import EarshotDiscovery
import EarshotRouter
import XCTest

/// A menu reader that counts its reads.
final class CountingMenuRead: @unchecked Sendable {
    var reads = 0
    let items: [MenuItem]
    init(_ items: [MenuItem]) { self.items = items }
    func read(_ bundleID: String) async -> [MenuItem] { reads += 1; return items }
}

enum MenuFixture {
    static let notes = "com.apple.Notes"
    static let items = [
        MenuItem(path: ["File", "New Note"], enabled: true, keys: "cmd+n"),
        MenuItem(path: ["Edit", "Undo"], enabled: true, keys: "cmd+z"),
        MenuItem(path: ["Edit", "Copy"], enabled: false, keys: "cmd+c"),
        MenuItem(path: ["Edit", "Select All"], enabled: true, keys: "cmd+a"),
        MenuItem(path: ["Disk", "Wipe Disk"], enabled: true),
    ]
}

final class MenuCacheTests: XCTestCase {
    func testElementsKeepEnabledItemsAndT4RiskyFlag() {
        let e = MenuCache.elements(MenuFixture.items)
        XCTAssertEqual(e.map(\.id), ["m:File>New Note", "m:Edit>Undo", "m:Edit>Select All", "m:Disk>Wipe Disk"])
        XCTAssertTrue(e.allSatisfy { $0.role == "AXMenuItem" })
        // "wipe" is in MenuIndex.riskyWords, not in SafetyPolicy (R-NV-5).
        XCTAssertEqual(e.filter(\.risky).map(\.label), ["Wipe Disk"])
    }

    func testCommandReadsOnlyTheCache() async {
        let reader = CountingMenuRead(MenuFixture.items)
        let cache = MenuCache(read: { await reader.read($0) })
        XCTAssertTrue(cache.cached(MenuFixture.notes).isEmpty, "no list yet: empty, and no read")
        XCTAssertEqual(reader.reads, 0)
        await cache.load(MenuFixture.notes)
        XCTAssertEqual(reader.reads, 1)

        let engine = TextEngine()
        engine.text = "select all"
        let runner = DryRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { MenuFixture.notes })
        p.menus = { cache.cached($0) }
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(reader.reads, 1, "the command must not read the menus")
        XCTAssertEqual(runner.runs.first?.0, .click(elementID: "m:Edit>Select All"))
        XCTAssertTrue(r.note.contains("0 elements, 4 menu items"), r.note)
    }

    func testMenusJoinTheScreenOfTheSameApp() {
        let p = CommandPipeline(engine: TextEngine(), router: CommandRouter(), actions: DryRunner(), names: FakeNames(),
                                apps: { [] }, allNames: { [] }, frontBundleID: { nil })
        p.menus = { $0 == "com.google.Chrome" ? MenuCache.elements(MenuFixture.items) : [] }
        let page = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "t", url: "https://example.org",
                                  elements: [ScreenElement(id: "e1", role: "AXLink", label: "Home", risky: false)])
        XCTAssertEqual(p.withMenus(page, front: "com.apple.Notes")?.elements.count, 5, "the screen's app decides")
        XCTAssertNil(p.withMenus(nil, front: nil))
        XCTAssertNil(p.withMenus(nil, front: "com.apple.Notes"), "no cached menus: no snapshot")
    }

    func testMenuTitleDoesNotMakeThePageSensitive() {
        let menu = MenuCache.elements([MenuItem(path: ["Safari", "Passwords…"], enabled: true)])
        let page = [ScreenElement(id: "e1", role: "AXButton", label: "Search", risky: false)]
        XCTAssertNil(SafetyPolicy.sensitive(url: "https://example.org", elements: page + menu))
        let field = [ScreenElement(id: "e2", role: "AXTextField", label: "Password", risky: false)]
        XCTAssertNotNil(SafetyPolicy.sensitive(url: "https://example.org", elements: field + menu))
    }

    /// Live test: "open FPL guru tab" was blocked as risky, because the tab title has "transfer" (R-NV-5).
    func testTabTitleMenuItemIsNotBlocked() async {
        let fpl = "FPL Guru — AI Fantasy Premier League transfer tips, captain picks & chip strategy | FPL Guru"
        let items = MenuIndex.flatten([MenuNode(title: "Tab", children: [MenuNode(title: fpl), MenuNode(title: "Close Tab")])],
                                      titles: [fpl + " - Memory usage - 491 MB"])
        let menu = MenuCache.elements(items)
        let engine = TextEngine()
        engine.text = "open FPL guru tab"
        let runner = DryRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.google.Chrome" })
        p.menus = { _ in menu }
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.first?.0, .click(elementID: MenuElements.id(["Tab", fpl])), r.note)
        XCTAssertFalse(r.note.contains("risky"), r.note)
    }
}
