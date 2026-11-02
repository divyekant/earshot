import Foundation

/// One command in the activity log. It holds no audio (R-MD-1) and no field text.
public struct ActivityRecord: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var at = Date()
    public var heard: String
    public var intent: String
    public var tier: RouterTier
    public var ok: Bool
    public var note: String
    /// Stage times in ms from the end of speech.
    public var stages: [String: Double]

    public init(heard: String, intent: String, tier: RouterTier, ok: Bool, note: String, stages: [String: Double]) {
        self.heard = heard; self.intent = intent; self.tier = tier; self.ok = ok; self.note = note; self.stages = stages
    }
}

/// Appends records to activity.jsonl in the store folder, and reads the last ones back.
public struct ActivityLog: Sendable {
    public let url: URL

    public init(store: Store = Store()) { url = store.folder.appendingPathComponent("activity.jsonl") }

    public func append(_ record: ActivityRecord) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try JSONEncoder().encode(record)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    public func last(_ count: Int) -> [ActivityRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").suffix(count).compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0.utf8)) }
    }
}
