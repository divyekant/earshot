@testable import EarshotCore
import Foundation
import XCTest

final class ActivityLogTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func record(_ n: Int, at: Date = Date()) -> ActivityRecord {
        var r = ActivityRecord(heard: "open app \(n)", intent: "→ App", tier: .rules, ok: true, note: "", stages: ["total": Double(n)])
        r.at = at
        return r
    }

    func testLastReadsTheEndInSmallBlocks() throws {
        let log = ActivityLog(store: Store(folder: folder))
        for n in 1...50 { try log.append(record(n)) }
        // A block of 100 bytes is shorter than one line: the read goes back block by block and keeps whole lines only.
        for block in [37, 100, 1000, 64 * 1024] {
            let last = log.last(7, block: block)
            XCTAssertEqual(last.map(\.heard), (44...50).map { "open app \($0)" }, "block \(block)")
        }
        XCTAssertEqual(log.last(500).count, 50)
        XCTAssertEqual(log.last(1).first?.heard, "open app 50")
        XCTAssertTrue(log.last(0).isEmpty)
    }

    func testLastWithNoFile() {
        XCTAssertTrue(ActivityLog(store: Store(folder: folder)).last(10).isEmpty)
    }

    func testLastSkipsABadLine() throws {
        let log = ActivityLog(store: Store(folder: folder))
        try log.append(record(1))
        let handle = try FileHandle(forWritingTo: log.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        try log.append(record(2))
        XCTAssertEqual(log.last(10).map(\.heard), ["open app 1", "open app 2"])
    }

    func testPruneKeeps30Days() throws {
        let log = ActivityLog(store: Store(folder: folder))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try log.append(record(1, at: now.addingTimeInterval(-40 * 86_400)))
        try log.append(record(2, at: now.addingTimeInterval(-31 * 86_400)))
        try log.append(record(3, at: now.addingTimeInterval(-29 * 86_400)))
        try log.append(record(4, at: now))
        XCTAssertEqual(ActivityLog.keepDays, 30)
        XCTAssertEqual(try log.prune(now: now), 2)
        XCTAssertEqual(log.last(10).map(\.heard), ["open app 3", "open app 4"])
        XCTAssertEqual(try log.prune(now: now), 0, "nothing more to remove")
        try log.append(record(5, at: now))
        XCTAssertEqual(log.last(10).count, 3, "appends go on after a prune")
    }

    func testPruneWithNoFile() throws {
        XCTAssertEqual(try ActivityLog(store: Store(folder: folder)).prune(), 0)
    }
}
