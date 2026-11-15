import XCTest
@testable import FootnoteCore

/// The rename from "PA" to "Footnote" (2026-11-15): a data folder with the old file names keeps all its data.
final class OldNamesTests: XCTestCase {
    func testAnOldStoreGetsTheNewNameAndKeepsItsItems() throws {
        let (e, _, clock) = makeEngine()
        e.handle(.command(id: "c1", lead: "todo", text: "buy fern seed", context: [:]))
        e.stop()
        let folder = e.folder
        let fm = FileManager.default
        // Make the folder of the old name: pa.sqlite, pa.log, one daily copy and one broken copy.
        try fm.moveItem(at: folder.appendingPathComponent("footnote.sqlite"), to: folder.appendingPathComponent("pa.sqlite"))
        for side in ["-wal", "-shm"] where fm.fileExists(atPath: folder.appendingPathComponent("footnote.sqlite\(side)").path) {
            try fm.moveItem(at: folder.appendingPathComponent("footnote.sqlite\(side)"),
                            to: folder.appendingPathComponent("pa.sqlite\(side)"))
        }
        try fm.moveItem(at: folder.appendingPathComponent("footnote.log"), to: folder.appendingPathComponent("pa.log"))
        let backups = folder.appendingPathComponent("backups", isDirectory: true)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("copy".utf8).write(to: backups.appendingPathComponent("pa-2026-11-10.sqlite"))
        try Data("broken".utf8).write(to: folder.appendingPathComponent("pa-broken-1.sqlite"))

        let again = Engine(folder: folder, clock: clock, output: MemoryOutput())
        again.start()
        defer { again.stop() }
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("pa.sqlite").path))
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("pa.log").path))
        XCTAssertTrue(fm.fileExists(atPath: backups.appendingPathComponent("footnote-2026-11-10.sqlite").path))
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("footnote-broken-1.sqlite").path))
        let titles = again.store?.items(where: "1 = 1").map(\.title) ?? []
        XCTAssertTrue(titles.contains { $0.contains("fern seed") }, "\(titles)")
        let log = try String(contentsOf: folder.appendingPathComponent("footnote.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("old-names"))
    }

    func testANewNameIsNeverReplaced() throws {
        let folder = tempFolder()
        try Data("new".utf8).write(to: folder.appendingPathComponent("footnote.log"))
        try Data("old".utf8).write(to: folder.appendingPathComponent("pa.log"))
        OldNames.migrate(folder: folder)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("footnote.log"), encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("pa.log").path))
    }
}
