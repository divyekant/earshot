import Foundation
import XCTest
@testable import PACore

/// Phase 5 (X1): the stdin reader of the PA left one block of about 16 KB for each message from earshot, because its
/// thread never drained its autorelease pool. 1,000 messages must add less than 0.5 MB of heap in use.
final class LineReaderTests: XCTestCase {
    func testLinesAndTheLastLineWithNoEnd() {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("a\n\nb\nc".utf8))
        pipe.fileHandleForWriting.closeFile()
        var got: [String] = []
        LineReader.run(pipe.fileHandleForReading) { got.append(String(decoding: $0, as: UTF8.self)) }
        XCTAssertEqual(got, ["a", "b", "c"])
    }

    func testThousandMessagesAddLessThanHalfAMegabyte() throws {
        #if !os(macOS)
        throw XCTSkip("the heap numbers are macOS numbers")
        #else
        func inUse() -> Int {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            return stats.size_in_use
        }
        let pipe = Pipe()
        let done = DispatchSemaphore(value: 0)
        let counted = NSLock()
        var count = 0
        var before = 0
        // A thread that never drains its own pool, as the reader thread of the PA.
        let thread = Thread {
            LineReader.run(pipe.fileHandleForReading) { _ in
                counted.lock(); count += 1; counted.unlock()
            }
            done.signal()
        }
        thread.start()
        let line = Data((#"{"type":"command","id":"m","lead":"what is due","text":"","context":{}}"# + "\n").utf8)
        func send(_ n: Int) {
            let target = count + n
            for _ in 0..<n {
                pipe.fileHandleForWriting.write(line)
                // One message at a time, as earshot sends them: each one is a read of its own.
                while true { counted.lock(); let c = count; counted.unlock(); if c >= target - n + 1 { break }; usleep(50) }
                break
            }
            for _ in 1..<n { pipe.fileHandleForWriting.write(line); usleep(200) }
            while true { counted.lock(); let c = count; counted.unlock(); if c >= target { break }; usleep(1000) }
        }
        send(100)
        before = inUse()
        send(1000)
        let grew = Double(inUse() - before) / 1_048_576
        print("LINE-READER heap grew \(String(format: "%.3f", grew)) MB for 1,000 messages")
        XCTAssertLessThan(grew, 0.5)
        pipe.fileHandleForWriting.closeFile()
        done.wait()
        #endif
    }
}
