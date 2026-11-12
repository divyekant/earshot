@testable import EarshotCore
import XCTest

/// The plugin contract data: manifest, approvals, messages (R-PL-1 to R-PL-4). Made-up plugins only.
final class PluginTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func write(_ id: String, _ json: String) throws {
        let dir = folder.appendingPathComponent("plugins/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("plugin.json"))
    }

    private let good = """
    {"contract": 1, "id": "pa", "name": "Helper", "version": "0.1.0", "leads": ["remind me to"],
     "context": ["app"], "run": ["./helper", "--serve"]}
    """

    func testManifestDecodesWithDefaults() throws {
        let m = try JSONDecoder().decode(PluginManifest.self, from: Data(#"{"contract":1,"id":"x","leads":["note"],"run":["/bin/cat"]}"#.utf8))
        XCTAssertEqual(m.name, "x")
        XCTAssertEqual(m.context, [])
        XCTAssertTrue(m.problems.isEmpty, "\(m.problems)")
    }

    func testManifestProblems() {
        var m = PluginManifest(id: "Bad Id", name: "B", leads: [], context: ["mail"], run: [""])
        m.contract = 2
        let p = m.problems
        XCTAssertEqual(p.count, 5, "\(p)")
    }

    /// The keys "document" and "selection" (docs/PLUGINS.md 5.1).
    func testDocumentAndSelectionKeys() {
        let m = PluginManifest(id: "pa", name: "PA", leads: ["note"], context: ["app", "document", "selection"], run: ["./pa"])
        XCTAssertTrue(m.problems.isEmpty, "\(m.problems)")
        XCTAssertEqual(PluginContract.documentPath("file:///Users/me/My%20Lease.pdf"), "/Users/me/My Lease.pdf")
        XCTAssertEqual(PluginContract.documentPath("/Users/me/notes.txt"), "/Users/me/notes.txt")
        XCTAssertNil(PluginContract.documentPath("https://example.com/a.pdf"))
        XCTAssertNil(PluginContract.documentPath(""))
    }

    func testWindowFolderFromItemAddresses() {
        let base = "file:///private/tmp/made-up/garden-papers/"
        // List or icon view: the items of the folder.
        XCTAssertEqual(PluginContract.windowFolder(title: "garden-papers", urls: [base + "seed-order.txt", base + "shed-plan.txt"]),
                       "/private/tmp/made-up/garden-papers")
        // The path bar alone (an empty folder).
        XCTAssertEqual(PluginContract.windowFolder(title: "garden-papers", urls: ["file:///private/tmp/made-up/", base]),
                       "/private/tmp/made-up/garden-papers")
        // Column view: other columns from the root, and an open subfolder of the same window.
        let columns = ["file:///Applications/", "file:///private/", "file:///private/tmp/made-up/", base,
                       base + "plans/", base + "plans/shed.txt", base + "hedge-quote.txt"]
        XCTAssertEqual(PluginContract.windowFolder(title: "garden-papers", urls: columns), "/private/tmp/made-up/garden-papers")
        // No folder with the name of the title, or no title.
        XCTAssertNil(PluginContract.windowFolder(title: "Recents", urls: [base + "seed-order.txt"]))
        XCTAssertNil(PluginContract.windowFolder(title: "", urls: [base + "seed-order.txt"]))
        XCTAssertNil(PluginContract.windowFolder(title: "garden-papers", urls: ["https://example.com/garden-papers/a"]))
        XCTAssertNil(PluginContract.selectionText("  \n"))
        XCTAssertNil(PluginContract.selectionText(nil))
        XCTAssertEqual(PluginContract.selectionText(String(repeating: "a", count: 5000))?.count, PluginContract.maxSelectionCharacters)
        XCTAssertTrue(PluginContract.contextText("selection").contains("selected"))
    }

    func testScanAndApproval() throws {
        try write("pa", good)
        let catalog = PluginCatalog(store: Store(folder: folder))
        var found = catalog.scan()
        XCTAssertEqual(found.map(\.id), ["pa"])
        XCTAssertFalse(found[0].approved, "a new plugin is not approved")
        XCTAssertTrue(found[0].problems.isEmpty, "\(found[0].problems)")

        try catalog.setApproved(found[0], true)
        found = catalog.scan()
        XCTAssertTrue(found[0].approved)

        // A changed manifest needs a new approval (R-PL-4).
        try write("pa", good.replacingOccurrences(of: "remind me to", with: "remind me"))
        XCTAssertFalse(catalog.scan()[0].approved)
    }

    func testFolderNameMustBeTheID() throws {
        try write("other", good)
        XCTAssertTrue(PluginCatalog(store: Store(folder: folder)).scan()[0].problems.contains("the id is not the folder name"))
    }

    func testBadManifestIsListedWithAProblem() throws {
        try write("broken", "{ not json")
        let found = PluginCatalog(store: Store(folder: folder)).scan()
        XCTAssertEqual(found.first?.problems, ["plugin.json is not valid"])
        XCTAssertEqual(found.first?.approved, false)
    }

    func testNoPluginsFolder() {
        XCTAssertTrue(PluginCatalog(store: Store(folder: folder)).scan().isEmpty)
    }

    func testCommandRequestEncodesOnlyItsFields() throws {
        let data = try JSONEncoder().encode(PluginRequest.command(id: "c1", lead: "note", text: "buy stamps", context: ["app": "x"]))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(object?.keys.map { $0 } ?? []), ["type", "id", "lead", "text", "context"])
    }

    func testAnswerTextIsCut() {
        let list = PluginMessage(type: "answer", kind: "list", text: "Due today", items: (1...12).map { "item \($0)" })
        let shown = list.shownText ?? ""
        XCTAssertTrue(shown.hasPrefix("Due today\n1. item 1"))
        XCTAssertTrue(shown.contains("10. item 10"))
        XCTAssertFalse(shown.contains("11. item 11"))
        XCTAssertTrue(shown.contains("… 2 more"))

        let long = PluginMessage(type: "answer", text: String(repeating: "a", count: 1000))
        XCTAssertEqual(long.shownText?.count, PluginContract.maxAnswerCharacters)
        XCTAssertNil(PluginMessage(type: "targets").shownText)
        XCTAssertNil(PluginMessage(type: "answer", text: "  ").shownText)
    }

    func testParseDropsBadLines() {
        XCTAssertNil(PluginMessage.parse(Data("not json".utf8)))
        XCTAssertNil(PluginMessage.parse(Data(repeating: 0x20, count: PluginContract.maxLineBytes + 1)))
        let m = PluginMessage.parse(Data(#"{"type":"answer","re":"c1","kind":"alert","text":"Time to stretch","extra":1}"#.utf8))
        XCTAssertEqual(m?.isAlert, true)
        XCTAssertEqual(m?.re, "c1")
    }

    /// "open <target>" opens a web address, a document or a folder. Never a program or a script (R-PL-3).
    func testTargetOpensOnlyDocuments() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        func file(_ name: String) throws -> String {
            let u = folder.appendingPathComponent(name)
            try Data("x".utf8).write(to: u)
            return u.path
        }
        let page = try file("today.html")
        XCTAssertNotNil(PluginTargetOpen.url(page).url)
        XCTAssertNotNil(PluginTargetOpen.url(try file("lease.PDF")).url)
        XCTAssertNotNil(PluginTargetOpen.url("https://example.com/today").url)
        XCTAssertNotNil(PluginTargetOpen.url(folder.path).url, "a plain folder opens in Finder")

        for name in ["run.sh", "run.command", "tool", "setup.pkg", "x.scpt", "x.webloc", "x.terminal"] {
            XCTAssertNil(PluginTargetOpen.url(try file(name)).url, name)
        }
        let app = folder.appendingPathComponent("Helper.app", isDirectory: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertNil(PluginTargetOpen.url(app.path).url, "an app bundle is a program")

        // A link with a document name to a script: earshot checks the file that the link points to.
        let link = folder.appendingPathComponent("link.html")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: try file("evil.sh"))
        XCTAssertNil(PluginTargetOpen.url(link.path).url)

        for bad in ["", "today.html", "file:///etc/hosts", "ftp://example.com/x", "javascript:alert(1)",
                    "x-apple.systempreferences:com.apple.preference.security", folder.appendingPathComponent("gone.html").path] {
            XCTAssertNil(PluginTargetOpen.url(bad).url, bad)
            XCTAssertNotNil(PluginTargetOpen.url(bad).why, bad)
        }
    }
}
