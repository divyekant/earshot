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
    {"contract": 1, "id": "footnote", "name": "Helper", "version": "0.1.0", "leads": ["remind me to"],
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
        let m = PluginManifest(id: "footnote", name: "Footnote", leads: ["note"], context: ["app", "document", "selection", "pageText"], run: ["./footnote"])
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
        try write("footnote", good)
        let catalog = PluginCatalog(store: Store(folder: folder))
        var found = catalog.scan()
        XCTAssertEqual(found.map(\.id), ["footnote"])
        XCTAssertFalse(found[0].approved, "a new plugin is not approved")
        XCTAssertTrue(found[0].problems.isEmpty, "\(found[0].problems)")

        try catalog.setApproved(found[0], true)
        found = catalog.scan()
        XCTAssertTrue(found[0].approved)

        // A changed manifest needs a new approval (R-PL-4).
        try write("footnote", good.replacingOccurrences(of: "remind me to", with: "remind me"))
        XCTAssertFalse(catalog.scan()[0].approved)
    }

    // MARK: Rename (docs/PLUGINS.md 2.1)

    private let oldManifest = """
    {"contract": 1, "id": "old-helper", "name": "Old", "version": "0.1.0", "leads": ["remind me to"],
     "context": ["app", "url"], "run": ["./old/run"]}
    """
    private let newManifest = """
    {"contract": 1, "id": "helper", "name": "Helper", "version": "0.2.0", "leads": ["remind me to"],
     "context": ["url", "app"], "run": ["./new/run"], "formerID": "old-helper"}
    """

    /// Installs the approved old plugin with one data file, and the new plugin. Returns the catalog.
    private func renameSetUp(new: String? = nil) throws -> PluginCatalog {
        let catalog = PluginCatalog(store: Store(folder: folder))
        try write("old-helper", oldManifest)
        try catalog.setApproved(catalog.scan()[0], true)
        let data = catalog.dataFolder.appendingPathComponent("old-helper/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: data.appendingPathComponent("store.sqlite"))
        try write("helper", new ?? newManifest)
        return catalog
    }

    func testARenameMovesTheDataAndTheApproval() throws {
        let catalog = try renameSetUp()
        let renames = catalog.pendingRenames()
        XCTAssertEqual(renames.map(\.from), ["old-helper"])
        XCTAssertEqual(renames.map(\.to), ["helper"])
        XCTAssertTrue(try catalog.apply(renames[0]).isEmpty)

        let fm = FileManager.default
        let moved = catalog.dataFolder.appendingPathComponent("helper/sub/store.sqlite")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "kept")
        XCTAssertFalse(fm.fileExists(atPath: catalog.dataFolder.appendingPathComponent("old-helper").path))
        XCTAssertFalse(fm.fileExists(atPath: catalog.folder.appendingPathComponent("old-helper").path))
        let found = catalog.scan()
        XCTAssertEqual(found.map(\.id), ["helper"])
        XCTAssertTrue(found[0].approved)
        XCTAssertNil(catalog.approvals["old-helper"])
        XCTAssertTrue(catalog.pendingRenames().isEmpty, "a rename happens one time")
    }

    /// Settings of the window (docs/PLUGINS.md 3.2) are part of the approval: new settings move the data, not the approval.
    func testARenameWithNewSettingsMovesTheDataButNotTheApproval() throws {
        let withSettings = newManifest.replacingOccurrences(of: #""formerID": "old-helper"}"#, with: """
            "formerID": "old-helper", "settings": [{"key": "rules.time", "label": "L", "choices": ["alert", "off"], "default": "alert"}]}
            """)
        XCTAssertNotEqual(withSettings, newManifest)
        let catalog = try renameSetUp(new: withSettings)
        let renames = catalog.pendingRenames()
        XCTAssertEqual(renames.map(\.to), ["helper"])
        XCTAssertNil(renames[0].newHash)
        try catalog.apply(renames[0])
        let moved = catalog.dataFolder.appendingPathComponent("helper/sub/store.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        let found = catalog.scan()
        XCTAssertEqual(found.map(\.id), ["helper"])
        XCTAssertFalse(found[0].approved, "the owner approves the new settings")
        XCTAssertNil(catalog.approvals["old-helper"])
        XCTAssertTrue(catalog.pendingRenames().isEmpty)
    }

    func testARenameKeepsTheFilesThatTheNewFolderHas() throws {
        let catalog = try renameSetUp()
        let fm = FileManager.default
        let newSub = catalog.dataFolder.appendingPathComponent("helper/sub", isDirectory: true)
        try fm.createDirectory(at: newSub, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: newSub.appendingPathComponent("store.sqlite"))
        try Data("model".utf8).write(to: newSub.appendingPathComponent("model.gguf"))
        try Data("old log".utf8).write(to: catalog.dataFolder.appendingPathComponent("old-helper/log.txt"))

        let kept = try catalog.apply(catalog.pendingRenames()[0])
        XCTAssertEqual(kept, ["sub/store.sqlite"])
        XCTAssertEqual(try String(contentsOf: newSub.appendingPathComponent("store.sqlite"), encoding: .utf8), "new")
        XCTAssertTrue(fm.fileExists(atPath: catalog.dataFolder.appendingPathComponent("helper/log.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: catalog.dataFolder.appendingPathComponent("old-helper/sub/store.sqlite").path),
                      "no data is deleted")
    }

    func testNoRenameIfTheOwnerDidNotApproveTheSameThings() throws {
        // Other leads, more context, a network host, or no approval of the old plugin: no rename.
        let changed = [
            newManifest.replacingOccurrences(of: "remind me to", with: "remind me"),
            newManifest.replacingOccurrences(of: #"["url", "app"]"#, with: #"["url", "app", "selection"]"#),
            newManifest.replacingOccurrences(of: #""formerID""#, with: #""network": ["example.com"], "formerID""#),
        ]
        for json in changed {
            try? FileManager.default.removeItem(at: folder)
            let catalog = try renameSetUp(new: json)
            XCTAssertTrue(catalog.pendingRenames().isEmpty, json)
        }
        try? FileManager.default.removeItem(at: folder)
        let catalog = try renameSetUp()
        try catalog.setApproved(catalog.scan().first { $0.id == "old-helper" }!, false)
        XCTAssertTrue(catalog.pendingRenames().isEmpty, "the old plugin is not approved")
        // The old manifest changed after the approval.
        try write("old-helper", oldManifest.replacingOccurrences(of: "0.1.0", with: "0.1.1"))
        try catalog.setApproved(catalog.scan().first { $0.id == "old-helper" }!, true)
        try write("old-helper", oldManifest)
        XCTAssertTrue(catalog.pendingRenames().isEmpty, "the old manifest is not the approved one")
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
        XCTAssertNotNil(PluginTargetOpen.url("message://%3Cabc123@mail.example.com%3E").url, "one mail in Mail")
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

        for bad in ["", "today.html", "file:///etc/hosts", "ftp://example.com/x", "javascript:alert(1)", "message:", "message://",
                    "x-apple.systempreferences:com.apple.preference.security", folder.appendingPathComponent("gone.html").path] {
            XCTAssertNil(PluginTargetOpen.url(bad).url, bad)
            XCTAssertNotNil(PluginTargetOpen.url(bad).why, bad)
        }
    }
}
