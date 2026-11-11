import Foundation
import XCTest
@testable import PACore
import PAMac
#if canImport(CoreServices)

/// Phase 2, Q6: the FSEvents watch of macOS on a made-up folder.
final class FSEventsTests: XCTestCase {
    func testANewFileComesToTheHandler() throws {
        let root = tempFolder().resolvingSymlinksInPath()
        let w = FSEventsWatcher()
        let got = expectation(description: "a change")
        got.assertForOverFulfill = false
        let target = root.appendingPathComponent("new-quote.txt")
        w.watch([root.path]) { paths in
            if paths.contains(where: { $0.hasSuffix("new-quote.txt") }) { got.fulfill() }
        }
        // FSEvents needs a short time to start the stream.
        Thread.sleep(forTimeInterval: 0.5)
        try Data("A made-up quote.".utf8).write(to: target)
        wait(for: [got], timeout: 10)
    }
}
#endif
