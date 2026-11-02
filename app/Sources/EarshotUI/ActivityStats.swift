import EarshotCore
import Foundation

/// Numbers for the Activity tab. Stage times are in ms from the end of speech, so the largest stage is the total.
public enum ActivityStats {
    /// The time from the end of speech to the last stage, or nil if the record has no stages.
    public static func total(_ record: ActivityRecord) -> Double? { record.stages.values.max() }

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
        public var count: Int
        public var okCount: Int
        public var medianMs: Double?
        public var p90Ms: Double?
        /// Records by router tier, for example ["rules": 40, "jev": 2].
        public var byTier: [String: Int]
    }

    public static func summary(_ records: [ActivityRecord]) -> Summary {
        let totals = records.compactMap(total)
        var byTier: [String: Int] = [:]
        for r in records { byTier[r.tier.rawValue, default: 0] += 1 }
        return Summary(count: records.count, okCount: records.filter(\.ok).count,
                       medianMs: percentile(totals, 0.5), p90Ms: percentile(totals, 0.9), byTier: byTier)
    }

    /// "42 commands · 40 OK · median 410 ms · p90 690 ms".
    public static func summaryLine(_ s: Summary) -> String {
        var parts = ["\(s.count) commands", "\(s.okCount) OK"]
        if let m = s.medianMs { parts.append("median \(Int(m.rounded())) ms") }
        if let p = s.p90Ms { parts.append("p90 \(Int(p.rounded())) ms") }
        return parts.joined(separator: " · ")
    }
}
