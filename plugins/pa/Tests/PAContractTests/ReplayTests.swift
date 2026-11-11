import Foundation
import XCTest

/// The go marks "No lost capture", "Speed", "No text in logs" and "No network" (build spec, section 12).
/// The program runs as earshot runs it: a child process with pipes. Made-up words only.
final class ReplayTests: XCTestCase {
    static let words = ["plumber", "tiles", "passport", "gardener", "invoice", "parcel", "boiler", "dentist", "kettle", "ferry"]

    /// 200 command lines, with odd input between them.
    func replayLines() -> (lines: [[String: Any]], captures: Int, odd: [String]) {
        var lines: [[String: Any]] = []
        var captures = 0
        let leads = ["remind me", "todo", "note", "task", "what is due", "where is", "new project", "snooze", "quiet", "what about"]
        for n in 0..<200 {
            let lead = leads[n % leads.count]
            let w = ReplayTests.words[n % ReplayTests.words.count]
            var text: String
            switch n % 20 {
            case 0: text = ""
            case 1: text = String(repeating: "x\(w) ", count: 2000)
            case 2: text = "call the \(w) 😀 \"now\" \\ back at 5"
            case 3: text = "ring the \(w) tomorrow at 9 #\(n)"
            default: text = "check the \(w) number \(n) by Friday"
            }
            if ["remind me", "todo", "note", "task"].contains(lead), !text.isEmpty { captures += 1 }
            lines.append(["type": "command", "id": "r\(n)", "lead": lead, "text": text, "context": ["app": "com.example.app"]])
        }
        let odd = ["not json at all", #"{"type":"mystery","x":1}"#, #"{"type":"command","id":"odd1","lead":"sing a song","text":"la"}"#,
                   #"{"type":"command"}"#, "{", String(repeating: "z", count: 70_000)]
        return (lines, captures, odd)
    }

    func testReplayNoLostCaptureSpeedAndNoTextInLogs() throws {
        // If the program stops, a write to its stdin must fail as an error, not stop the test run.
        signal(SIGPIPE, SIG_IGN)
        let p = try ContractTests.Plugin()
        p.send(["type": "hello", "contract": 1])
        let (lines, captures, odd) = replayLines()
        var times: [Double] = []
        for (n, l) in lines.enumerated() {
            if n % 40 == 5 { for o in odd { p.send(o) } }
            let start = Date()
            p.send(l)
            let a = p.answer(l["id"] as! String)
            XCTAssertNotNil(a, "no answer for \(l["id"]!)")
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        XCTAssertNotNil(p.answer("odd1"))
        XCTAssertTrue(p.process.isRunning, "The program stopped.")
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2], p90 = sorted[Int(Double(sorted.count) * 0.9)]
        print(String(format: "MARK speed: 200 commands, median %.1f ms, slowest 1 in 10 %.1f ms, max %.1f ms", median, p90, sorted.last!))
        XCTAssertLessThanOrEqual(median, 100)
        XCTAssertLessThanOrEqual(p90, 100)
        XCTAssertNotNil(p.close())

        // One row for each capture with words. The same capture in 60 s keeps one: the replay has none.
        let db = p.folder.appendingPathComponent("pa.sqlite").path
        guard FileManager.default.fileExists(atPath: "/usr/bin/sqlite3") else { throw XCTSkip("no /usr/bin/sqlite3 to read the store") }
        let count = try sqlite(db, "SELECT COUNT(*) FROM item")
        print("MARK replay: \(captures) captures sent, \(count.trimmingCharacters(in: .whitespacesAndNewlines)) rows in the store")
        XCTAssertEqual(Int(count.trimmingCharacters(in: .whitespacesAndNewlines)), captures)

        // No words of the owner in the log and in the event table.
        let log = try String(contentsOf: p.folder.appendingPathComponent("pa.log"), encoding: .utf8)
        let events = try sqlite(db, "SELECT * FROM event")
        for w in ReplayTests.words {
            XCTAssertFalse(log.contains(w), "pa.log has \(w)")
            XCTAssertFalse(events.contains(w), "the event table has \(w)")
        }
        print("MARK no text in logs: pa.log \(log.count) characters, event table \(events.split(separator: "\n").count) rows, no fixture words")
    }

    func sqlite(_ db: String, _ sql: String) throws -> String {
        let pr = Process()
        pr.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        pr.arguments = [db, sql]
        let pipe = Pipe()
        pr.standardOutput = pipe
        try pr.run()
        pr.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// The sources have no network code.
    func testNoNetworkCodeInTheSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let banned = ["URLSession", "NWConnection", "CFSocket", "socket(", "import Network", "CFStream", "NSURLConnection"]
        var files = 0
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let url as URL in e where url.pathExtension == "swift" {
            files += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for b in banned { XCTAssertFalse(text.contains(b), "\(url.lastPathComponent) has \(b)") }
        }
        print("MARK no network: \(files) source files, no network interface")
    }

    /// The program with the network denied by the macOS sandbox. Each function must work.
    func testRunsWithTheNetworkDenied() throws {
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: "/usr/bin/sandbox-exec") else { throw XCTSkip("no sandbox-exec") }
        let p = try ContractTests.Plugin(sandbox: "(version 1)(allow default)(deny network*)")
        p.send(["type": "hello", "contract": 1])
        p.send(["type": "command", "id": "n1", "lead": "remind me", "text": "to call the plumber at 5", "context": [:]])
        p.send(["type": "command", "id": "n2", "lead": "what is due", "text": "", "context": [:]])
        let a1 = p.answer("n1"), a2 = p.answer("n2")
        XCTAssertEqual((a1?["text"] as? String)?.hasPrefix("Reminder · "), true)
        XCTAssertEqual(a2?["kind"] as? String, "list")
        print("MARK network denied: capture and list work")
        XCTAssertNotNil(p.close())
        #else
        throw XCTSkip("macOS only")
        #endif
    }
}
