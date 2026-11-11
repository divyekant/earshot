import Foundation
import XCTest
@testable import PACore

final class StoreTests: XCTestCase {
    func testMigrationMakesAllTables() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        let names = try store.db.query("SELECT name FROM sqlite_master WHERE type IN ('table')").compactMap { $0.first?.text }
        for t in ["item", "project", "project_alias", "doc", "alert", "last_list", "mirror", "event", "meta", "item_fts"] {
            XCTAssertTrue(names.contains(t), "no table \(t)")
        }
        XCTAssertEqual(try store.db.query("PRAGMA user_version").first?.first?.int, Int64(Store.schemaVersion))
    }

    func testInsertSearchAndEventHasNoText() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        var it = Item(kind: .todo, said: "call the tile shop for kitchen", title: "call the tile shop", createdAt: wed(10))
        it.id = try store.insert(it)
        XCTAssertEqual(store.item(it.id)?.title, "call the tile shop")
        let hits = store.search(["tile"], limit: 5)
        XCTAssertEqual(hits.first?.0, .item)
        XCTAssertEqual(hits.first?.1, it.id)
        let events = try store.db.query("SELECT * FROM event")
        XCTAssertEqual(events.count, 1)
        for row in events { for v in row { XCTAssertFalse((v.text ?? "").contains("tile")) } }
    }

    func testBrokenFileStartsANewStore() throws {
        let folder = tempFolder()
        let url = folder.appendingPathComponent("pa.sqlite")
        try Data(repeating: 0x41, count: 4096).write(to: url)
        let store = try Store(url: url, now: wed(10))
        XCTAssertNotNil(store.recoveredFrom)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.recoveredFrom!.path))
        XCTAssertNoThrow(try store.insert(Item(kind: .note, said: "a", title: "a", createdAt: wed(10))))
    }

    func testBackupKeepsSevenCopies() throws {
        let folder = tempFolder()
        let store = try Store(url: folder.appendingPathComponent("pa.sqlite"))
        let backups = folder.appendingPathComponent("backups")
        for d in 1...9 { try store.backup(folder: backups, day: Day(2026, 11, d), keep: 7) }
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(files.count, 7)
        XCTAssertEqual(files.first, "pa-2026-11-03.sqlite")
    }
}
