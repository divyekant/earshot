import Foundation
import PACore

/// The date detector of macOS (NSDataDetector, type date). Probe 2 of the build measures it on the 100 time
/// phrases. On a system with no detector it finds nothing.
public struct SystemDateDetector: TimeDetector {
    public init() {}

    public func detect(_ text: String, now: Date, calendar: Calendar) -> [DetectedTime] {
        #if canImport(Darwin)
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let ns = text as NSString
        let matches = d.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard let date = m.date, let r = Range(m.range, in: text) else { return nil }
            let lower = text.distance(from: text.startIndex, to: r.lowerBound)
            let upper = text.distance(from: text.startIndex, to: r.upperBound)
            // The detector gives 12:00 for a day with no time. The check below is a guess, the probe records it.
            let c = calendar.dateComponents([.hour, .minute], from: date)
            let hasClock = !(c.hour == 12 && c.minute == 0 && !text[r].lowercased().contains("noon") && !text[r].contains("12"))
            return DetectedTime(date: date, range: lower..<upper, hasClock: hasClock)
        }
        #else
        return []
        #endif
    }
}
