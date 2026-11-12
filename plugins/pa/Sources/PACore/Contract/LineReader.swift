import Foundation

/// Reads JSON lines from earshot (stdin of the PA). It gives each line that is not empty, and returns at the end of
/// the input. A line with no end that is longer than `maxLine` bytes is dropped.
public enum LineReader {
    public static let maxLine = 1_048_576

    public static func run(_ input: FileHandle, maxLine: Int = LineReader.maxLine, onLine: (Data) -> Void) {
        var buffer = Data()
        while true {
            // Phase 5 (X1): the reader thread never returns, so its autorelease pool never drained. Each read left
            // one block of about 16 KB (one for each message). Each read now has its own pool.
            let chunk = autoreleasepool { input.availableData }
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if !line.isEmpty { onLine(line) }
            }
            if buffer.count > maxLine { buffer.removeAll() }
        }
        if !buffer.isEmpty { onLine(buffer) }
    }
}
