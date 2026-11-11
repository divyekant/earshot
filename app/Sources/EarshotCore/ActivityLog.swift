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
/// The log keeps `keepDays` days. `prune` removes older records.
public struct ActivityLog: Sendable {
    public let url: URL
    /// The days of records that the log keeps.
    public static let keepDays = 30
    /// One lock for all logs: an append must not go in while `prune` writes the file again.
    private static let lock = NSLock()

    public init(store: Store = Store()) { url = store.folder.appendingPathComponent("activity.jsonl") }

    public func append(_ record: ActivityRecord) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
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

    /// The last `count` records, oldest first. It reads only the end of the file, in blocks of `block` bytes.
    public func last(_ count: Int, block: Int = 64 * 1024) -> [ActivityRecord] {
        guard count > 0, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return [] }
        var offset = size
        var data = Data()
        // Read back until the data holds more than `count` line ends, or the start of the file.
        // One more line end than the count makes sure that the first kept line is whole.
        while offset > 0, data.reduce(0, { $0 + ($1 == 0x0A ? 1 : 0) }) <= count {
            let step = min(UInt64(max(block, 1)), offset)
            offset -= step
            guard (try? handle.seek(toOffset: offset)) != nil, let chunk = try? handle.read(upToCount: Int(step)) else { break }
            data = chunk + data
        }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        // A line that the read cut at the front is not whole: drop it.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        let decoder = JSONDecoder()
        return lines.suffix(count).compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0)) }
    }

    /// Removes the records older than `days` days. A line that does not decode stays.
    /// - Returns: the number of records that it removed.
    @discardableResult
    public func prune(days: Int = keepDays, now: Date = Date()) throws -> Int {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let decoder = JSONDecoder()
        var kept = Data()
        var removed = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let r = try? decoder.decode(ActivityRecord.self, from: Data(line)), r.at < cutoff {
                removed += 1
                continue
            }
            kept.append(contentsOf: line)
            kept.append(0x0A)
        }
        if removed > 0 { try kept.write(to: url, options: .atomic) }
        return removed
    }
}
