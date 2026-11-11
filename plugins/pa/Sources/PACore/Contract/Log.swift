import Foundation

/// The log of the PA, pa.log in the data folder. It keeps times, types and record numbers. It never keeps the
/// words of the owner (build rule 8). stderr goes to /dev/null, so this file is the only log.
public final class PALog {
    let url: URL?
    private var handle: FileHandle?
    /// The log starts again when it is larger than this count of bytes.
    let limit: UInt64 = 1_000_000

    public init(url: URL?) {
        self.url = url
        guard let url else { return }
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        if let size = try? handle?.seekToEnd(), size > limit {
            try? handle?.truncate(atOffset: 0)
        }
    }

    /// Writes one line. `fields` must not hold words of the owner: only types, numbers and fixed labels.
    public func write(_ at: Date, _ type: String, _ fields: [String: String] = [:]) {
        guard let handle else { return }
        let iso = ISO8601DateFormatter().string(from: at)
        var line = "\(iso) \(type)"
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) { line += " \(k)=\(v)" }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
