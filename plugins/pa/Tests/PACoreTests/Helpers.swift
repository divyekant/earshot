import Foundation
@testable import PACore

/// A new empty data folder for one test.
func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pa-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Wed 11 Nov 2026 at the clock time, in Europe/London.
func wed(_ hour: Int, _ minute: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/London")!
    return c.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
}

/// One line of the fixture time-phrases.tsv.
struct TimeCase {
    var lead: String
    var now: Date
    var words: String
    var kind: String
    var expected: String
}

func timeCases(file: String = "time-phrases") -> [TimeCase] {
    let url = Bundle.module.url(forResource: file, withExtension: "tsv", subdirectory: "Fixtures")!
    let text = try! String(contentsOf: url, encoding: .utf8)
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/London")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { line in
        let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return TimeCase(lead: p[0], now: f.date(from: p[1])!, words: p[2], kind: p[3], expected: p[4])
    }
}

/// An engine with a fixed clock, a memory output and a new folder.
func makeEngine(now: Date = wed(10), reminders: ReminderStore? = nil) -> (Engine, MemoryOutput, FixedClock) {
    let clock = FixedClock(now)
    let out = MemoryOutput()
    let e = Engine(folder: tempFolder(), clock: clock, output: out, reminders: reminders)
    e.start()
    // The phase 1 tests check captures with no project focus. ProposalTests checks the focus (phase 2, 8.3).
    e.settings.projectFocusMinutes = 0
    return (e, out, clock)
}

extension Outgoing {
    var text: String {
        if case .answer(_, _, let t, _) = self { return t }
        return ""
    }
    var items: [String] {
        if case .answer(_, _, _, let i) = self { return i }
        return []
    }
    var kind: AnswerKind? {
        if case .answer(_, let k, _, _) = self { return k }
        return nil
    }
    var re: String? {
        if case .answer(let r, _, _, _) = self { return r }
        return nil
    }
}
