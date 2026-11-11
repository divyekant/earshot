import EarshotCore
import Foundation

/// Numbers for the Activity tab. Stage times are in ms from the end of speech.
public enum ActivityStats {
    /// Stages that are not a time from the end of speech: the audio length, and the time that a bare "type" waits.
    static let notTimes: Set<String> = ["speech.audio", "dictation.armed"]

    /// The time from the end of speech to the end of the command, or nil if the record has no stages.
    /// It is the "total" stage. An older record with no "total" uses its largest time stage.
    public static func total(_ record: ActivityRecord) -> Double? {
        if let total = record.stages["total"] { return total }
        return record.stages.filter { !notTimes.contains($0.key) }.values.max()
    }

    /// True if the record is a turn with words: the speech engine heard words, or the owner typed a command.
    /// A rejected wake, a near miss, a dropped turn, a voice teach step, a turn with no words and a speech error
    /// are not commands.
    public static func hasWords(_ record: ActivityRecord) -> Bool {
        !record.heard.isEmpty && !record.stages.isEmpty
    }

    /// The stages in time order, for example "text 120 · route 135 · chat 380".
    public static func stageLine(_ record: ActivityRecord) -> String {
        record.stages.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
            .map { "\($0.key) \(Int($0.value.rounded()))" }
            .joined(separator: " · ")
    }

    /// The value at the given fraction (0...1) of the sorted values, by the nearest-rank method.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public struct Summary: Equatable, Sendable {
        /// The turns with words.
        public var count: Int
        public var okCount: Int
        public var medianMs: Double?
        public var p90Ms: Double?
        /// Turns with words by router tier, for example ["rules": 40, "jev": 2].
        public var byTier: [String: Int]
        /// The other records: rejected wakes, near misses, dropped turns, turns with no words.
        public var otherCount: Int = 0
    }

    /// The summary counts only the turns with words (`hasWords`).
    public static func summary(_ records: [ActivityRecord]) -> Summary {
        let turns = records.filter(hasWords)
        let totals = turns.compactMap(total)
        var byTier: [String: Int] = [:]
        for r in turns { byTier[r.tier.rawValue, default: 0] += 1 }
        return Summary(count: turns.count, okCount: turns.filter(\.ok).count,
                       medianMs: percentile(totals, 0.5), p90Ms: percentile(totals, 0.9), byTier: byTier,
                       otherCount: records.count - turns.count)
    }

    /// "42 commands · 40 OK · median 410 ms · p90 690 ms · 12 other records".
    public static func summaryLine(_ s: Summary) -> String {
        var parts = ["\(s.count) commands", "\(s.okCount) OK"]
        if let m = s.medianMs { parts.append("median \(Int(m.rounded())) ms") }
        if let p = s.p90Ms { parts.append("p90 \(Int(p.rounded())) ms") }
        if s.otherCount > 0 { parts.append("\(s.otherCount) other record\(s.otherCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
