import EarshotCore
import XCTest
@testable import EarshotUI

/// The pages of a plugin in the window and the panel (docs/PLUGINS.md 5.4, R-PL-3).
final class PluginPagesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ id: String, approved: Bool = true, problems: [String] = []) -> PluginEntry {
        let manifest = PluginManifest(id: id, name: "Name \(id)", leads: ["x"], run: ["./x"])
        return PluginEntry(manifest: manifest, folder: root, hash: "h", approved: approved, problems: problems)
    }

    private func writeIndex(_ id: String) throws {
        let folder = root.appendingPathComponent(id).appendingPathComponent("pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<p>hi</p>".utf8).write(to: folder.appendingPathComponent("index.html"))
    }

    func testOnlyApprovedPluginsWithAnIndexGetALink() throws {
        try writeIndex("footnote")
        try writeIndex("other")
        try writeIndex("broken")
        let entries = [entry("footnote"), entry("other", approved: false), entry("broken", problems: ["p"]),
                       entry("nopages")]
        let found = PluginPages.find(entries: entries, dataFolder: root)
        XCTAssertEqual(found.map(\.id), ["footnote"])
        XCTAssertEqual(found.first?.name, "Name footnote")
    }

    func testLinksInTheFolderStayAndOthersFollowTheOpenRule() throws {
        try writeIndex("footnote")
        let page = PluginPages(id: "footnote", name: "Footnote", folder: root.appendingPathComponent("footnote/pages"))
        XCTAssertEqual(page.place(of: page.folder.appendingPathComponent("all-open.html")), .inView)
        XCTAssertEqual(page.place(of: page.folder.appendingPathComponent("../../x.html")), .blocked, "a file that is not there")
        XCTAssertEqual(page.place(of: URL(string: "https://example.com/a")!), .outside)
        XCTAssertEqual(page.place(of: URL(string: "message://%3Cid%40x%3E")!), .outside)
        XCTAssertEqual(page.place(of: URL(string: "javascript:alert(1)")!), .blocked)
        XCTAssertEqual(page.place(of: URL(string: "ftp://example.com/a")!), .blocked)
        let app = root.appendingPathComponent("Tool.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertEqual(page.place(of: app), .blocked, "an app is not a document")
    }

    func testPluginLinksComeBeforeTheFixedPages() {
        let p = PluginPages(id: "footnote", name: "Footnote", folder: root)
        XCTAssertEqual(ManageLink.all(plugins: [p]).map(\.title), ["Footnote", "Settings", "Activity", "Plugins", "Advanced"])
    }
}
