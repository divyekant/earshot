import Foundation

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum Clock {
    static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(since t0: UInt64) -> Double { Double(nowNs() &- t0) / 1_000_000 }
}

/// Records the time of each stage, in milliseconds after t0.
final class Stopwatch {
    let t0: UInt64
    private(set) var marks: [(String, Double)] = []

    init(t0: UInt64 = Clock.nowNs()) { self.t0 = t0 }

    func mark(_ name: String) { marks.append((name, Clock.ms(since: t0))) }

    func value(_ name: String) -> Double? { marks.last(where: { $0.0 == name })?.1 }

    var dictionary: [String: Double] {
        var out: [String: Double] = [:]
        for (name, ms) in marks { out[name] = (ms * 10).rounded() / 10 }
        return out
    }

    var summary: String {
        marks.map { "\($0.0) \(Int($0.1.rounded()))" }.joined(separator: " · ")
    }
}

func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
}

/// Polls `condition` until it is true or the time runs out.
/// The sleep between polls lets the main run loop work.
@MainActor
func waitUntil(timeoutMs: Int, intervalMs: Int = 10, _ condition: () -> Bool) async -> Bool {
    let t0 = Clock.nowNs()
    while true {
        if condition() { return true }
        if Clock.ms(since: t0) >= Double(timeoutMs) { return false }
        await sleepMs(intervalMs)
    }
}

enum Paths {
    /// The probe directory: three levels above this source file.
    static let probeDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static var apps: URL { probeDir.appendingPathComponent("apps.json") }
    static var people: URL { probeDir.appendingPathComponent("people.json") }
    static var logs: URL { probeDir.appendingPathComponent("logs") }
}

/// Writes one JSON object per line to probe/logs/. Git ignores logs/.
final class RunLog {
    let url: URL
    private let handle: FileHandle

    init(kind: String) throws {
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        let stamp = RunLog.stamp()
        url = Paths.logs.appendingPathComponent("e0-\(kind)-\(stamp).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    func write(_ object: [String: Any]) {
        var obj = object
        obj["at"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(obj),
              var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        else { return }
        data.append(0x0A)
        handle.write(data)
    }
}

enum Text {
    /// Lowercase letters and digits only, words joined by one space.
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// The normalized text with no spaces. "Whats App" and "WhatsApp" have the same key.
    static func key(_ s: String) -> String { normalize(s).replacingOccurrences(of: " ", with: "") }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    /// 1.0 is the same text. 0.0 has nothing in common.
    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        if longest == 0 { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(longest)
    }

    /// Removes control characters, so typed text can never contain Return or Tab.
    static func printable(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: kept)
        return String(view)
    }
}

enum Stats {
    static func median(_ xs: [Double]) -> Double? { percentile(xs, 0.5) }

    static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        let index = max(0, min(sorted.count - 1, Int((p * Double(sorted.count)).rounded(.up)) - 1))
        return sorted[index]
    }

    static func ms(_ x: Double?) -> String { x.map { "\(Int($0.rounded())) ms" } ?? "-" }
}
