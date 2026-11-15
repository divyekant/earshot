import EarshotCore
import XCTest

/// Plugin settings in the window (docs/PLUGINS.md 3.2, R-PL-4).
final class PluginSettingsTests: XCTestCase {
    private let rule = PluginSetting(key: "rules.time", label: "A reminder reaches its time",
                                     choices: ["alert", "list", "off"], default: "alert")

    private func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("settings.json")
    }

    func testAWriteChangesOnlyItsKey() throws {
        let url = try tempFile()
        try Data(#"{"morningTime":"09:00","rules":{"due":"alert","time":"list"},"flagsMuted":["a@b.c"]}"#.utf8).write(to: url)
        let file = PluginSettingsFile(url: url)
        XCTAssertEqual(file.value(rule), "list")
        try file.set(rule, to: "off")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(o["morningTime"] as? String, "09:00")
        XCTAssertEqual(o["flagsMuted"] as? [String], ["a@b.c"])
        let rules = try XCTUnwrap(o["rules"] as? [String: Any])
        XCTAssertEqual(rules["time"] as? String, "off")
        XCTAssertEqual(rules["due"] as? String, "alert")
    }

    func testMissingFileOrUnknownValueGivesTheDefault() throws {
        let url = try tempFile()
        XCTAssertEqual(PluginSettingsFile(url: url).value(rule), "alert")
        try Data(#"{"rules":{"time":"loud"}}"#.utf8).write(to: url)
        XCTAssertEqual(PluginSettingsFile(url: url).value(rule), "alert")
        XCTAssertThrowsError(try PluginSettingsFile(url: url).set(rule, to: "loud"))
        try PluginSettingsFile(url: url).set(rule, to: "list")
        XCTAssertEqual(PluginSettingsFile(url: url).value(rule), "list")
    }

    func testBadSettingsAreProblems() {
        let bad = [
            PluginSetting(key: "../x", label: "a", choices: ["a"], default: "a"),
            PluginSetting(key: "a", label: "a", choices: [], default: "a"),
            PluginSetting(key: "b", label: "b", choices: ["x"], default: "y"),
            PluginSetting(key: "b", label: "", choices: ["x"], default: "x"),
        ]
        let p = PluginSetting.problems(bad)
        XCTAssertTrue(p.contains("bad setting key \"../x\""))
        XCTAssertTrue(p.contains("the setting \"a\" has no choices"))
        XCTAssertTrue(p.contains("the default of \"b\" is not one of its choices"))
        XCTAssertTrue(p.contains("the setting \"b\" is there twice"))
        XCTAssertTrue(p.contains("the setting \"b\" has no label"))
        XCTAssertTrue(PluginSetting.problems([rule]).isEmpty)
    }

    func testManifestReadsSettingsAndAnOldManifestHasNone() throws {
        let old = #"{"contract":1,"id":"x","leads":["x y"],"run":["./x"]}"#
        XCTAssertEqual(try JSONDecoder().decode(PluginManifest.self, from: Data(old.utf8)).settings, [])
        let new = #"{"contract":1,"id":"x","leads":["x y"],"run":["./x"],"settings":[{"key":"rules.time","label":"L","choices":["alert","off"],"default":"off","group":"G"}]}"#
        let m = try JSONDecoder().decode(PluginManifest.self, from: Data(new.utf8))
        XCTAssertEqual(m.settings.first?.key, "rules.time")
        XCTAssertEqual(m.settings.first?.group, "G")
        XCTAssertTrue(m.problems.isEmpty)
    }
}
