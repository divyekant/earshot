import Foundation
import XCTest

/// Follow-up R3: the model runs in a worker process. The tests use the hash model in the worker
/// (`"searchModel": "hash-worker"`), so that they need no model file. All words are made-up.
final class WorkerTests: XCTestCase {
    func log(_ p: ContractTests.Plugin) -> String {
        (try? String(contentsOf: p.folder.appendingPathComponent("pa.log"), encoding: .utf8)) ?? ""
    }

    /// The process ids of the workers in the log, in order.
    func workers(_ p: ContractTests.Plugin) -> [Int32] {
        log(p).split(separator: "\n").compactMap { line -> Int32? in
            guard line.contains(" model-loaded "), let r = line.range(of: "worker=") else { return nil }
            return Int32(line[r.upperBound...].prefix { $0.isNumber })
        }
    }

    func waitFor(_ timeout: TimeInterval, _ ok: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if ok() { return true }; usleep(20_000) }
        return ok()
    }

    func testAKilledWorkerStopsNoCommandAndANewWorkerStarts() throws {
        signal(SIGPIPE, SIG_IGN)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pa-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"searchModel": "hash-worker"}"#.utf8).write(to: folder.appendingPathComponent("settings.json"))
        let doc = folder.appendingPathComponent("made-up-tile-quote.txt")
        try Data("Quote from Harbour Ceramics for the floor tiles. The porcelain tiles cost 42 pounds per square metre.".utf8).write(to: doc)

        let p = try ContractTests.Plugin(folder: folder)
        p.send(["type": "hello", "contract": 1])
        p.send(["type": "command", "id": "k1", "lead": "keep this", "text": "", "context": ["document": doc.path]])
        XCTAssertNotNil(p.answer("k1"))
        // The first search loads the model in the background; the search after it uses the worker.
        p.send(["type": "command", "id": "w1", "lead": "where is", "text": "porcelain price", "context": [:]])
        XCTAssertNotNil(p.answer("w1"))
        XCTAssertTrue(waitFor(10) { !workers(p).isEmpty }, "no worker started:\n\(log(p))")
        let first = workers(p)[0]
        XCTAssertNotEqual(first, 0)

        // Kill the worker. The PA must answer each command, and keep each capture.
        kill(first, SIGKILL)
        usleep(200_000)
        p.send(["type": "command", "id": "c1", "lead": "todo", "text": "order the grout today", "context": [:]])
        XCTAssertEqual((p.answer("c1")?["text"] as? String)?.hasPrefix("To-do · "), true)
        p.send(["type": "command", "id": "w2", "lead": "where is", "text": "porcelain tiles", "context": [:]])
        XCTAssertNotNil(p.answer("w2"), "no answer to a search after the worker stopped")
        // A next search starts a new worker.
        XCTAssertTrue(waitFor(10) {
            p.send(["type": "command", "id": "w3-\(UUID().uuidString)", "lead": "where is", "text": "floor tiles", "context": [:]])
            usleep(300_000)
            return workers(p).count >= 2
        }, "no new worker after the kill:\n\(log(p))")
        XCTAssertNotEqual(workers(p).last, first)
        XCTAssertTrue(p.process.isRunning, "the PA stopped")
        XCTAssertNotNil(p.close())
        XCTAssertTrue(log(p).contains("model-fault"), log(p))
        print("MARK worker: killed worker \(first); the PA answered each command; new worker \(workers(p).last ?? 0)")
    }
}

