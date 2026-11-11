import Foundation
import XCTest
@testable import PACore
import PAMac

/// The probes of the build (phase1-build-spec, section 7). They print their results for the pull request.
final class ProbeTests: XCTestCase {
    /// Probe 3: the full-text search of the system SQLite.
    func testProbe3FullTextSearch() throws {
        let db = try SQLite(path: ":memory:")
        var fts5 = true, fts4 = true
        do { try db.exec("CREATE VIRTUAL TABLE t5 USING fts5(x)") } catch { fts5 = false }
        do { try db.exec("CREATE VIRTUAL TABLE t4 USING fts4(x)") } catch { fts4 = false }
        print("PROBE3 sqlite=\(SQLite.libraryVersion) fts5=\(fts5) fts4=\(fts4)")
        #if os(macOS)
        XCTAssertTrue(fts5, "The SQLite of macOS has no FTS5.")
        #endif
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        print("PROBE3 store search index: \(store.searchKind.rawValue)")
    }

    /// Probe 2: the date detector of macOS on the 100 time phrases. It prints a table: phrase, found or not, result.
    /// NSDataDetector has no reference date: it reads the phrases against the real time of the test run.
    func testProbe2DateDetector() throws {
        #if os(macOS)
        let det = SystemDateDetector()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "EEE yyyy-MM-dd HH:mm"
        let runNow = Date()
        var found = 0, spans = 0
        var lines: [String] = ["PROBE2 run at \(f.string(from: runNow))", "PROBE2 | words | found | phrase | result | expected (at the fixture time)"]
        for c in timeCases() {
            let hits = det.detect(c.words, now: runNow, calendar: cal)
            if let h = hits.last {
                found += 1
                let chars = Array(c.words)
                let phrase = String(chars[h.range.clamped(to: 0..<chars.count)])
                if c.kind != "none" { spans += 1 }
                lines.append("PROBE2 | \(c.words) | yes | \(phrase) | \(f.string(from: h.date))\(h.hasClock ? "" : " (no clock)") | \(c.expected)")
            } else {
                lines.append("PROBE2 | \(c.words) | no | | | \(c.expected)")
            }
        }
        let withTime = timeCases().filter { $0.kind != "none" }.count
        lines.append("PROBE2 found \(found) of 100. Found in phrases with a time: \(spans) of \(withTime). Found in phrases with no time: \(found - spans) of \(100 - withTime).")
        print(lines.joined(separator: "\n"))
        #else
        throw XCTSkip("The date detector is only on macOS.")
        #endif
    }
}
