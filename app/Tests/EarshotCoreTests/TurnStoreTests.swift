import Foundation
import XCTest
@testable import EarshotCore

// E7: the turn recorder keeps numbers only, for 7 days, in the turns folder.
final class TurnStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-turns-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func record(_ kind: TurnRecord.Kind = .rejectedWake, frames: Bool = true) -> TurnRecord {
        var r = TurnRecord(kind: kind, outcome: "rejected", levelFrameMs: 20, levels: [-60, nil, -30.5], floorDb: -61.2,
                           turnStart: 2)
        let template = WakeTemplate(frames: 2, width: 2, half: Data(count: 8))
        r.add(wake: WakeHit(phrase: "hey jarvis", prerollSeconds: 1, voiceScore: 0.21, isOwner: false, matchScore: 0.31,
                            matchWorst: 0.4),
              gate: 0.35, trace: WakeTrace(frames: frames ? template : nil, scores: [0.5, nil], firstFrame: 3,
                                           matchStart: 0, matchEnd: 1, limit: 0.33))
        return r
    }

    private func day(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: text + "T12:00:00Z")!
    }

    func testRecordsGoToTheFileOfTheDayAndComeBack() {
        let today = day("2026-11-11")
        let store = TurnStore(store: Store(folder: folder), keepsFrames: true, now: { today })
        var r = record()
        r.add(activity: ActivityRecord(heard: "", intent: "none", tier: .none, ok: false, note: "wake phrase in another voice",
                                       stages: [:]))
        store.append(r)
        let back = store.all()
        XCTAssertEqual(back, [r])
        XCTAssertEqual(back.first?.levels, [-60, nil, -30.5], "a muted frame stays nil")
        XCTAssertNotNil(back.first?.trace?.frames)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("turns/2026-11-11.jsonl").path))
    }

    func testNoFramesIfTheOwnerDidNotAllowThem() {
        let store = TurnStore(store: Store(folder: folder), keepsFrames: false)
        store.append(record())
        let back = store.all()
        XCTAssertNil(back.first?.trace?.frames)
        XCTAssertEqual(back.first?.trace?.scores, [0.5, nil], "the scores stay")
    }

    func testFramesStopAfterTheLimitOfTheHour() {
        let today = day("2026-11-11")
        let store = TurnStore(store: Store(folder: folder), keepsFrames: true, now: { today })
        for _ in 0..<(TurnStore.framesPerHour + 5) { store.append(record()) }
        let back = store.all()
        XCTAssertEqual(back.count, TurnStore.framesPerHour + 5, "the scores of every match stay")
        XCTAssertEqual(back.filter { $0.trace?.frames != nil }.count, TurnStore.framesPerHour)
    }

    func testDaysOlderThanSevenGo() throws {
        let turns = folder.appendingPathComponent("turns")
        try FileManager.default.createDirectory(at: turns, withIntermediateDirectories: true)
        for name in ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-10"] {
            try Data().write(to: turns.appendingPathComponent(name + ".jsonl"))
        }
        let today = day("2026-11-11")
        let store = TurnStore(store: Store(folder: folder), keepsFrames: true, now: { today })
        store.append(record())
        store.flush()
        let names = try FileManager.default.contentsOfDirectory(atPath: turns.path).sorted()
        XCTAssertEqual(names, ["2026-11-05.jsonl", "2026-11-10.jsonl", "2026-11-11.jsonl"], "today and the 6 days before")
    }

    func testRemoveAllDeletesTheFolder() {
        let store = TurnStore(store: Store(folder: folder), keepsFrames: true)
        store.append(record())
        store.flush()
        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("turns").path))
    }

    func testRoundingDropsValuesThatAreNotFinite() {
        XCTAssertEqual(TurnRecord.rounded(-31.234, places: 10), -31.2)
        XCTAssertNil(TurnRecord.rounded(.infinity, places: 10))
        XCTAssertNil(TurnRecord.rounded(nil, places: 10))
    }

    func testTheRecorderIsOnByDefaultAndOldSettingsReadIt() throws {
        XCTAssertTrue(EarshotSettings().recordTurns)
        let old = try JSONDecoder().decode(EarshotSettings.self, from: Data(#"{"mode":"alwaysOn"}"#.utf8))
        XCTAssertTrue(old.recordTurns)
        XCTAssertEqual(old.mode, .alwaysOn)
    }
}
