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
}
