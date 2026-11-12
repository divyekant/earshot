import XCTest
@testable import PACore

/// Phase 5, X5: the counts command. Numbers only, no text of the store.
final class CountsTests: XCTestCase {
    func say(_ e: Engine, _ lead: String, _ text: String = "") {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
    }

    /// Each string value in the output, with its path.
    func strings(_ v: Any, _ path: String = "") -> [(String, String)] {
        if let d = v as? [String: Any] { return d.flatMap { strings($0.value, path + "." + $0.key) } }
        if let a = v as? [Any] { return a.flatMap { strings($0, path + "[]") } }
        if let s = v as? String { return [(path, s)] }
        return []
    }

    func testCountsHaveNoTextOfTheStore() throws {
        let (e, _, clock) = makeEngine()
        say(e, "remind me", "to call the plumber zebrafinch tomorrow at 9")
        say(e, "todo", "buy zebrafinch seed")
        say(e, "note", "the zebrafinch code is 4417")
        say(e, "where is", "zebrafinch")
        say(e, "where is", "plumber")
        clock.now = clock.now.addingTimeInterval(60)
        e.stop()

        let line = Counts.json(folder: e.folder, now: clock.now)
        XCTAssertFalse(line.contains("zebrafinch"))
        XCTAssertFalse(line.contains("plumber"))
        XCTAssertFalse(line.contains("4417"))

        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        // The only string values: the version, and dates.
        let iso = ISO8601DateFormatter()
        for (path, s) in strings(obj) {
            XCTAssertTrue(path == ".version" || iso.date(from: s) != nil, "string value at \(path)")
        }
        let total = try XCTUnwrap(obj["total"] as? [String: Any])
        let captures = try XCTUnwrap(total["captures"] as? [String: Int])
        XCTAssertEqual(captures["reminder"], 1)
        XCTAssertEqual(captures["todo"], 1)
        XCTAssertEqual(captures["note"], 1)
        let commands = try XCTUnwrap(total["commands"] as? [String: Int])
        XCTAssertEqual(commands["whereIs"], 2)
        XCTAssertEqual(commands["remindMe"], 1)
        XCTAssertEqual((total["searches"] as? [String: Any])?["count"] as? Int, 2)
        XCTAssertTrue((total["searches"] as? [String: Any])?["openAfterSearch"] is NSNull)
        XCTAssertNotNil(obj["commandCountsFrom"] as? String)
        // The last 7 days have the same counts here.
        XCTAssertEqual(((obj["last7Days"] as? [String: Any])?["commands"] as? [String: Int])?["whereIs"], 2)
    }

    func testCountsOfAnEmptyFolderWriteNothing() throws {
        let folder = tempFolder()
        let line = Counts.json(folder: folder)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(((obj["total"] as? [String: Any])?["captures"] as? [String: Int])?["todo"], 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("settings.json").path))
    }
}
