import Foundation
import XCTest
@testable import PACore

/// The go mark "Time phrases" (build spec, section 12): 95 or more correct, 2 or fewer with a wrong time.
final class TimeReaderTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    func format(_ r: TimeReading) -> (String, String) {
        guard r.kind != .none else { return ("none", "none") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        if let at = r.at { return (r.kind.rawValue, f.string(from: at)) }
        return (r.kind.rawValue, r.day?.description ?? "?")
    }

    func testHundredTimePhrases() {
        let reader = TimeReader(calendar: cal)
        var correct = 0, wrong = 0, noTime = 0
        var lines: [String] = []
        for c in timeCases() {
            let r = reader.read(c.words, now: c.now, todo: c.lead == "todo")
            let (kind, value) = format(r)
            if kind == c.kind && value == c.expected {
                correct += 1
            } else if kind == "none" {
                noTime += 1
                lines.append("MARK time none  | \(c.words) | expected \(c.kind) \(c.expected)")
            } else {
                wrong += 1
                lines.append("MARK time WRONG | \(c.words) | got \(kind) \(value) | expected \(c.kind) \(c.expected)")
            }
        }
        print((lines + ["MARK time phrases: correct \(correct), wrong \(wrong), no time \(noTime) (of 100)"]).joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(correct, 95)
        XCTAssertLessThanOrEqual(wrong, 2)
    }

    func testCutOnlyAtTheEnds() {
        let reader = TimeReader(calendar: cal)
        XCTAssertEqual(reader.read("call the plumber at 5", now: wed(10)).rest, "call the plumber")
        XCTAssertEqual(reader.read("tomorrow call the bank at 3", now: wed(10)).rest, "call the bank")
        XCTAssertEqual(reader.read("call Sam tomorrow to talk about the gate at 5", now: wed(10)).rest,
                       "call Sam tomorrow to talk about the gate")
        XCTAssertEqual(reader.read("send the tax papers by Friday.", now: wed(10), todo: true).rest, "send the tax papers")
    }

    func testUnsureGivesNoTime() {
        let reader = TimeReader(calendar: cal)
        let r = reader.read("call the plumber at 5ish tomorrowish pm", now: wed(10))
        XCTAssertEqual(r.kind, .none)
        XCTAssertEqual(r.rest, "call the plumber at 5ish tomorrowish pm")
    }
}

/// A second set of 30 phrases, written after the rules. It shows how the rules do on phrases that they were not
/// made for. It prints the result. The go mark uses the first set.
final class TimeReaderHoldoutTests: XCTestCase {
    func testHoldoutSet() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let reader = TimeReader(calendar: cal)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var correct = 0, wrong = 0, none = 0
        for c in timeCases(file: "time-phrases-holdout") {
            let r = reader.read(c.words, now: c.now, todo: c.lead == "todo")
            let kind = r.kind.rawValue
            let value = r.kind == .none ? "none" : (r.at.map { f.string(from: $0) } ?? r.day?.description ?? "?")
            if kind == c.kind && value == c.expected { correct += 1 }
            else if r.kind == .none { none += 1; print("MARK holdout none  | \(c.words) | expected \(c.expected)") }
            else { wrong += 1; print("MARK holdout WRONG | \(c.words) | got \(kind) \(value) | expected \(c.kind) \(c.expected)") }
        }
        print("MARK holdout phrases: correct \(correct), wrong \(wrong), no time \(none) (of 30)")
    }
}
