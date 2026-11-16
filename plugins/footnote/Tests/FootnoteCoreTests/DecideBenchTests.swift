import XCTest
@testable import FootnoteCore

/// The rules arm of E13 (docs/experiments/E13-footnote-decision-model.md). R-FN-4: the bench prints counts only.
final class DecideBenchTests: XCTestCase {
    func item(_ id: String, kind: String = "mail", body: String, owner: String = "Ana Lim") -> String {
        let obj: [String: Any] = [
            "id": id, "kind": kind, "owner": ["name": owner, "address": "ana.lim@example.com"],
            "now": "2026-11-03T08:00:00Z", "from_name": kind == "note" ? "" : "Sam Lee",
            "from_address": kind == "note" ? "" : "sam.lee@example.org", "to": kind == "note" ? [] : ["ana.lim@example.com"],
            "cc": [], "subject": "Form", "date": "2026-11-03T08:00:00Z", "list_unsubscribe": false, "precedence": "",
            "auto_submitted": false, "junk": false, "replied": false, "body": body, "sender_known": true,
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
    }

    func testPredictionsAndFactsLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("decide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let items = dir.appendingPathComponent("items.jsonl"), pred = dir.appendingPathComponent("pred.tsv")
        let lines = [
            item("m1", body: "Hi Ana,\n\nCould you send me the signed form by tomorrow?\n\nThanks,\nSam"),
            item("m2", body: "Hi Ana,\n\nThe photos from the trip are online now.\n\nSam"),
            item("n1", kind: "note", body: "Ideas for the garden.\nCall the plumber today."),
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: items, atomically: true, encoding: .utf8)
        var printed: [String] = []
        let bench = DecideBench()
        bench.out = { printed.append($0) }
        try bench.run(items: items, predictions: pred)
        let rows = try String(contentsOf: pred, encoding: .utf8).split(separator: "\n").map { $0.components(separatedBy: "\t") }
        XCTAssertEqual(rows[0], ["id", "need", "need_score", "when", "sentence", "facts"])
        XCTAssertEqual(rows.count, 4)
        let m1 = rows[1]
        XCTAssertEqual(m1[1], "1")
        XCTAssertEqual(m1[3], "list")
        XCTAssertEqual(m1[4], "Could you send me the signed form by tomorrow?")
        XCTAssertEqual(m1[5], "owner: Ana Lim | kind: mail | sender: person | to: 1 | limit: tomorrow | weekday: Tue")
        XCTAssertEqual(rows[2][1], "0")
        XCTAssertTrue(rows[3][5].hasPrefix("owner: Ana Lim | kind: note | sender: owner | to: 0"))
        // Counts only: no text of an item in the printed line.
        XCTAssertEqual(printed.count, 1)
        XCTAssertFalse(printed[0].contains("form"))
    }
}
