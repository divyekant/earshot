import EarshotCore
import Foundation
import XCTest
@testable import EarshotWake

// E7: the frames around a match, for the turn recorder. Memory only until the store.
final class FrameRingTests: XCTestCase {
    private func frame(_ value: Float) -> [Float] { [Float](repeating: value, count: 4) }

    func testTraceStartsBeforeTheMatchAndEndsAtTheLastFrame() {
        var ring = FrameRing()
        for i in 0..<40 { ring.add(frame(Float(i)), score: i == 5 ? .infinity : Double(i) / 100) }
        let trace = ring.trace(matchStart: 25, matchEnd: 34, limit: 0.33)
        XCTAssertEqual(trace?.firstFrame, 25 - FrameRing.leadFrames)
        XCTAssertEqual(trace?.matchStart, FrameRing.leadFrames)
        XCTAssertEqual(trace?.matchEnd, FrameRing.leadFrames + 9)
        XCTAssertEqual(trace?.scores.count, 40 - (25 - FrameRing.leadFrames))
        XCTAssertEqual(trace?.scores.first ?? nil, 0.13)
        let frames = trace?.frames.map(WakeTemplates.unpack) ?? []
        XCTAssertEqual(frames.first, frame(13), "the frames come back from the 16-bit floats")
        XCTAssertEqual(frames.count, trace?.scores.count)
    }

    func testAScoreThatIsNotFiniteIsNil() {
        var ring = FrameRing()
        for i in 0..<10 { ring.add(frame(1), score: i < 3 ? .infinity : 0.5) }
        let scores = ring.trace(matchStart: 0, matchEnd: 9, limit: 0.33)?.scores ?? []
        XCTAssertEqual(scores.count, 10)
        XCTAssertNil(scores.first.flatMap { $0 })
        XCTAssertEqual(scores.last.flatMap { $0 }, 0.5)
    }

    func testTraceKeepsAtMostFiveSeconds() {
        var ring = FrameRing()
        for i in 0..<400 { ring.add(frame(Float(i % 7)), score: 0.5) }
        let trace = ring.trace(matchStart: 100, matchEnd: 399, limit: 0.33)
        XCTAssertEqual(trace?.scores.count, FrameRing.traceFrames)
        XCTAssertEqual(trace?.firstFrame, 400 - FrameRing.traceFrames)
        XCTAssertLessThan(trace?.matchStart ?? 0, 0, "the match started before the kept frames")
    }

    func testResetCountsFromZeroAgain() {
        var ring = FrameRing()
        for _ in 0..<10 { ring.add(frame(1), score: 0.5) }
        ring.reset()
        ring.add(frame(2), score: 0.4)
        XCTAssertEqual(ring.lastIndex, 0)
        XCTAssertNil(ring.trace(matchStart: 0, matchEnd: 3, limit: 0.33), "the match ends after the last frame")
    }
}
